import { loadConfig } from "./config.js";
import { createRepository } from "./repository.js";
import { buildServer } from "./server.js";

const config = loadConfig();
const repository = createRepository(config);
await repository.initialize();
const app = await buildServer(config, repository);

const shutdown = async (signal: string): Promise<void> => {
  app.log.info({ signal }, "Shutting down");
  await app.close();
  await repository.close();
  process.exit(0);
};

process.once("SIGTERM", () => void shutdown("SIGTERM"));
process.once("SIGINT", () => void shutdown("SIGINT"));

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error);
  await repository.close();
  process.exit(1);
}
