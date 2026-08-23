import { Document, NodeIO } from "@gltf-transform/core";
import sharp from "sharp";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import { validateAndNormalizeGlb } from "../src/validation/gltf.js";

const config = loadConfig({ NODE_ENV: "test", MOCK_PROVIDERS: "true" });

async function fixture(primitiveCount = 1, textureSize = 1): Promise<Buffer> {
  const document = new Document();
  const buffer = document.createBuffer();
  const image = await sharp({
    create: {
      width: textureSize,
      height: textureSize,
      channels: 4,
      background: { r: 124, g: 76, b: 255, alpha: 1 },
    },
  })
    .png()
    .toBuffer();
  const texture = document.createTexture("Color").setImage(new Uint8Array(image)).setMimeType("image/png");
  const material = document.createMaterial("Gloss").setBaseColorTexture(texture);
  const mesh = document.createMesh("Accessory");

  for (let index = 0; index < primitiveCount; index += 1) {
    const x = index * 4;
    const positions = document
      .createAccessor(`Positions ${index}`)
      .setType("VEC3")
      .setArray(new Float32Array([1 + x, 1, 1, -1 + x, -1, 1, -1 + x, 1, -1, 1 + x, -1, -1]))
      .setBuffer(buffer);
    const indices = document
      .createAccessor(`Indices ${index}`)
      .setType("SCALAR")
      .setArray(new Uint16Array([0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]))
      .setBuffer(buffer);
    const texcoords = document
      .createAccessor(`UV ${index}`)
      .setType("VEC2")
      .setArray(new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]))
      .setBuffer(buffer);
    mesh.addPrimitive(
      document
        .createPrimitive()
        .setAttribute("POSITION", positions)
        .setAttribute("TEXCOORD_0", texcoords)
        .setIndices(indices)
        .setMaterial(material),
    );
  }

  document.createScene("Scene").addChild(document.createNode("Accessory Root").setMesh(mesh));
  return Buffer.from(await new NodeIO().writeBinary(document));
}

describe("validateAndNormalizeGlb", () => {
  it("accepts one textured watertight mesh", async () => {
    const result = await validateAndNormalizeGlb(await fixture(), config);
    expect(result).toMatchObject({ triangles: 4, vertices: 4, textureWidth: 1, textureHeight: 1 });
    expect(result.glb.byteLength).toBeGreaterThan(0);
  });

  it("resizes oversized embedded textures to the Roblox limit", async () => {
    const result = await validateAndNormalizeGlb(await fixture(1, 2050), config);
    expect(result.textureWidth).toBe(2048);
    expect(result.textureHeight).toBe(2048);
  });

  it("joins compatible Smart Topology parts into one MeshPart", async () => {
    const result = await validateAndNormalizeGlb(await fixture(2), config);
    expect(result).toMatchObject({ triangles: 8, vertices: 8 });
    const normalized = await new NodeIO().readBinary(new Uint8Array(result.glb));
    expect(normalized.getRoot().listMeshes()).toHaveLength(1);
    expect(normalized.getRoot().listMeshes()[0]?.listPrimitives()).toHaveLength(1);
  });

  it("repairs a simple open boundary before Roblox upload", async () => {
    const document = await new NodeIO().readBinary(new Uint8Array(await fixture()));
    const primitive = document.getRoot().listMeshes()[0]?.listPrimitives()[0];
    primitive?.getIndices()?.setArray(new Uint16Array([0, 2, 1, 0, 1, 3, 0, 3, 2]));
    const glb = Buffer.from(await new NodeIO().writeBinary(document));
    await expect(validateAndNormalizeGlb(glb, config)).resolves.toMatchObject({ triangles: 4, vertices: 4 });
  });

  it("caps a larger simple boundary with validated attributes", async () => {
    const document = await new NodeIO().readBinary(new Uint8Array(await fixture()));
    const primitive = document.getRoot().listMeshes()[0]?.listPrimitives()[0];
    primitive
      ?.getAttribute("POSITION")
      ?.setArray(new Float32Array([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0, 0, 0, 1]));
    primitive
      ?.getAttribute("TEXCOORD_0")
      ?.setArray(new Float32Array([0, 0, 1, 0, 1, 1, 0, 1, 0.5, 0.5]));
    primitive?.getIndices()?.setArray(new Uint16Array([0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4]));
    const glb = Buffer.from(await new NodeIO().writeBinary(document));
    await expect(validateAndNormalizeGlb(glb, config)).resolves.toMatchObject({ triangles: 8, vertices: 6 });
  });

  it("still rejects non-manifold geometry that cannot be repaired safely", async () => {
    const document = await new NodeIO().readBinary(new Uint8Array(await fixture()));
    const primitive = document.getRoot().listMeshes()[0]?.listPrimitives()[0];
    const position = primitive?.getAttribute("POSITION");
    const texcoord = primitive?.getAttribute("TEXCOORD_0");
    const indices = primitive?.getIndices();
    position?.setArray(new Float32Array([...(position.getArray() ?? []), 0, 0, 2]));
    texcoord?.setArray(new Float32Array([...(texcoord.getArray() ?? []), 0.5, 0.5]));
    indices?.setArray(new Uint16Array([...(indices.getArray() ?? []), 0, 1, 4]));
    const glb = Buffer.from(await new NodeIO().writeBinary(document));
    await expect(validateAndNormalizeGlb(glb, config)).rejects.toMatchObject({ code: "NOT_WATERTIGHT" });
  });
});
