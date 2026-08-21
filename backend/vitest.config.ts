import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  root: fileURLToPath(new URL(".", import.meta.url)),
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    exclude: ["dist/**", "node_modules/**"],
    coverage: { reporter: ["text", "json-summary"] },
  },
});
