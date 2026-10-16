import { afterEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";
import { JobRunner } from "../src/pipeline.js";
import { MemoryJobRepository } from "../src/repository.js";
import { createJobSchema } from "../src/types.js";

const runners: JobRunner[] = [];
afterEach(() => {
  runners.splice(0).forEach((runner) => runner.close());
  vi.useRealTimers();
});

async function fixture() {
  vi.useFakeTimers();
  const config = loadConfig({ NODE_ENV: "test", MOCK_PROVIDERS: "true", MAX_CONCURRENT_JOBS: "1" });
  const repository = new MemoryJobRepository();
  const logger = { info: vi.fn(), error: vi.fn() };
  const create = (requestId: string) => repository.create(createJobSchema.parse({
    requestId, playerUserId: 123, kind: "TEXT_TO_3D", filteredPrompt: "A polished silver crown",
    accessoryType: "Hat", context: { universeId: 0, placeId: 0, gameJobId: "local-only-test" },
  }));
  const first = await create("worker_first_request_12345");
  const second = await create("worker_second_request_12345");
  const runner = new JobRunner(config, repository, logger);
  runners.push(runner);
  return { repository, logger, first, second, runner };
}

describe("worker infrastructure error boundary", () => {
  it("contains an initial database read failure, continues the queue, and permits later recovery", async () => {
    const { repository, logger, first, second, runner } = await fixture();
    const get = repository.get.bind(repository);
    let databaseUnavailable = true;
    repository.get = vi.fn(async (id: string) => {
      if (id === first.id && databaseUnavailable) throw new Error("Database connection interrupted");
      return get(id);
    });

    runner.enqueue(first.id);
    runner.enqueue(second.id);
    await vi.runAllTimersAsync();

    expect((await get(second.id))?.status).toBe("SUCCEEDED");
    expect((await get(first.id))?.status).toBe("QUEUED");
    expect(logger.error).toHaveBeenCalledWith(
      expect.objectContaining({ jobId: first.id, error: expect.any(Error) }),
      "Worker could not load or persist its job",
    );
    expect((await repository.listRecoverable()).map((job) => job.id)).toContain(first.id);

    databaseUnavailable = false;
    runner.enqueue(first.id);
    await vi.runAllTimersAsync();
    expect((await get(first.id))?.status).toBe("SUCCEEDED");
  });

  it("contains an unavailable failure-checkpoint write without replaying work or stopping another job", async () => {
    const { repository, logger, first, second, runner } = await fixture();
    const update = repository.update.bind(repository);
    repository.update = vi.fn(async (id, patch) => {
      if (id === first.id) throw new Error("Database writes unavailable");
      return update(id, patch);
    });

    runner.enqueue(first.id);
    runner.enqueue(second.id);
    await vi.runAllTimersAsync();

    expect((await repository.get(second.id))?.status).toBe("SUCCEEDED");
    expect((await repository.get(first.id))?.status).toBe("QUEUED");
    expect(logger.error).toHaveBeenCalledTimes(2);
    expect(logger.error).toHaveBeenLastCalledWith(
      expect.objectContaining({ jobId: first.id }), "Worker could not load or persist its job",
    );
    expect(vi.mocked(repository.update).mock.calls.filter(([id]) => id === first.id)).toHaveLength(2);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("recovers nonterminal jobs once and leaves completed jobs unchanged", async () => {
    const { repository, first, second, runner } = await fixture();
    await repository.update(first.id, { status: "SUCCEEDED", progress: 100, output: { modelAssetId: 987 } });
    const update = vi.spyOn(repository, "update");

    await runner.recover();
    runner.enqueue(second.id);
    runner.enqueue(first.id);
    await vi.runAllTimersAsync();

    expect((await repository.get(first.id))?.output.modelAssetId).toBe(987);
    expect(update.mock.calls.filter(([id]) => id === first.id)).toHaveLength(0);
    expect(update.mock.calls.filter(([id]) => id === second.id)).toHaveLength(1);
    expect((await repository.get(second.id))?.status).toBe("SUCCEEDED");
  });
});
