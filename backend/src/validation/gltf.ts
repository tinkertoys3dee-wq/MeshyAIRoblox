import { NodeIO, Primitive, PropertyType } from "@gltf-transform/core";
import { dedup, flatten, join } from "@gltf-transform/functions";
import sharp from "sharp";
import type { AppConfig } from "../config.js";
import { PipelineError } from "../types.js";

export type ValidationResult = {
  glb: Buffer;
  triangles: number;
  vertices: number;
  textureWidth: number;
  textureHeight: number;
  textures: Buffer[];
};

export async function validateAndNormalizeGlb(input: Buffer, config: AppConfig): Promise<ValidationResult> {
  const io = new NodeIO();
  let document;
  try {
    document = await io.readBinary(new Uint8Array(input));
  } catch (error) {
    throw new PipelineError("INVALID_GLB", error instanceof Error ? error.message : "Unable to read GLB", false);
  }

  // Smart Topology may return separate, compatible object parts. Flatten and
  // join those parts before validation so a multi-part design can still import
  // as the single MeshPart required for a rigid Roblox accessory.
  try {
    await document.transform(
      dedup({ propertyTypes: [PropertyType.MATERIAL] }),
      flatten(),
      join({ keepNamed: false }),
    );
  } catch (error) {
    throw new PipelineError(
      "MESH_JOIN_FAILED",
      error instanceof Error ? error.message : "Unable to combine generated mesh parts",
      false,
    );
  }

  if (document.getRoot().listAnimations().length > 0 || document.getRoot().listSkins().length > 0) {
    throw new PipelineError("RIGGED_MODEL", "Rigid accessories cannot contain animation or skin data", false);
  }

  const meshes = document.getRoot().listMeshes();
  if (meshes.length !== 1) {
    throw new PipelineError("MULTI_MESH", `Rigid accessories require one mesh; provider returned ${meshes.length}`, false);
  }
  const primitives = meshes[0]?.listPrimitives() ?? [];
  if (primitives.length !== 1) {
    throw new PipelineError(
      "MULTI_PRIMITIVE",
      `Rigid accessories must import as one MeshPart; provider returned ${primitives.length} primitives`,
      false,
    );
  }
  const meshNodes = document.getRoot().listNodes().filter((node) => node.getMesh());
  if (meshNodes.length !== 1) {
    throw new PipelineError(
      "MULTI_MESH_NODE",
      `Rigid accessories must import as one MeshPart; provider returned ${meshNodes.length} mesh nodes`,
      false,
    );
  }

  let triangles = 0;
  let vertices = 0;
  for (const primitive of primitives) {
    if (primitive.getMode() !== Primitive.Mode.TRIANGLES) {
      throw new PipelineError("NON_TRIANGLE_PRIMITIVE", "Generated mesh contains unsupported primitive modes", false);
    }
    const position = primitive.getAttribute("POSITION");
    if (!position) throw new PipelineError("MISSING_POSITIONS", "Generated mesh has no positions", false);
    const positions = position.getArray();
    if (!positions || Array.from(positions).some((value) => !Number.isFinite(value))) {
      throw new PipelineError("NON_FINITE_GEOMETRY", "Generated mesh contains non-finite vertex coordinates", false);
    }
    const texcoord = primitive.getAttribute("TEXCOORD_0");
    const texcoords = texcoord?.getArray();
    if (!texcoord || !texcoords || Array.from(texcoords).some((value) => !Number.isFinite(value))) {
      throw new PipelineError("MISSING_UV", "Generated textured mesh has no usable UV coordinates", false);
    }
    if (!primitive.getMaterial()?.getBaseColorTexture()) {
      throw new PipelineError("MISSING_TEXTURE", "Generated mesh has no base-color texture", false);
    }
    vertices += position.getCount();
    const indices = primitive.getIndices();
    triangles += Math.floor((indices?.getCount() ?? position.getCount()) / 3);
    assertWatertight(positions, indices?.getArray());
  }

  if (triangles <= 0 || vertices <= 0) {
    throw new PipelineError("EMPTY_MESH", "Generated mesh contains no usable geometry", false);
  }
  if (triangles > config.limits.maxTriangles) {
    throw new PipelineError(
      "TRIANGLE_LIMIT",
      `Generated mesh has ${triangles} triangles; maximum is ${config.limits.maxTriangles}`,
      false,
    );
  }
  if (vertices > config.limits.maxVertices) {
    throw new PipelineError(
      "VERTEX_LIMIT",
      `Generated mesh has ${vertices} vertices; maximum is ${config.limits.maxVertices}`,
      false,
    );
  }

  let textureWidth = 0;
  let textureHeight = 0;
  let textureCount = 0;
  const normalizedTextures: Buffer[] = [];
  for (const texture of document.getRoot().listTextures()) {
    const image = texture.getImage();
    if (!image) continue;
    textureCount += 1;
    const sourceImage = Buffer.from(image);
    const metadata = await sharp(sourceImage).metadata();
    let width = metadata.width ?? 0;
    let height = metadata.height ?? 0;
    if (width <= 0 || height <= 0) {
      throw new PipelineError("INVALID_TEXTURE", "Generated model contains an unreadable texture", false);
    }
    let transformer = sharp(sourceImage);
    if (width > config.limits.maxTextureSize || height > config.limits.maxTextureSize) {
      transformer = transformer.resize({
        width: config.limits.maxTextureSize,
        height: config.limits.maxTextureSize,
        fit: "inside",
        withoutEnlargement: true,
      });
    }
    const normalizedImage = await transformer.png({ compressionLevel: 9 }).toBuffer();
    texture.setImage(new Uint8Array(normalizedImage));
    texture.setMimeType("image/png");
    const normalizedMetadata = await sharp(normalizedImage).metadata();
    width = normalizedMetadata.width ?? 0;
    height = normalizedMetadata.height ?? 0;
    textureWidth = Math.max(textureWidth, width);
    textureHeight = Math.max(textureHeight, height);
    normalizedTextures.push(normalizedImage);
  }
  if (textureCount === 0) {
    throw new PipelineError("MISSING_TEXTURE", "Textured generation returned no embedded texture", false);
  }

  const normalized = await io.writeBinary(document);
  if (normalized.byteLength > config.limits.maxModelBytes) {
    throw new PipelineError(
      "MODEL_FILE_LIMIT",
      `Normalized GLB is ${normalized.byteLength} bytes; maximum is ${config.limits.maxModelBytes}`,
      false,
    );
  }
  return {
    glb: Buffer.from(normalized),
    triangles,
    vertices,
    textureWidth,
    textureHeight,
    textures: normalizedTextures,
  };
}

function assertWatertight(
  positions: ArrayLike<number>,
  rawIndices: ArrayLike<number> | null | undefined,
): void {
  const vertexCount = Math.floor(positions.length / 3);
  const indices = rawIndices ? Array.from(rawIndices) : Array.from({ length: vertexCount }, (_, index) => index);
  if (indices.length % 3 !== 0) {
    throw new PipelineError("INVALID_TRIANGLES", "Generated mesh has an incomplete triangle", false);
  }

  // glTF commonly splits vertices along UV or normal seams. Weld by position
  // before counting edges so a geometrically closed surface is not rejected
  // merely because its texture coordinates use separate vertex records.
  const welded = new Map<string, number>();
  const canonical = new Array<number>(vertexCount);
  for (let index = 0; index < vertexCount; index += 1) {
    const offset = index * 3;
    const key = `${quantize(positions[offset] ?? 0)},${quantize(positions[offset + 1] ?? 0)},${quantize(positions[offset + 2] ?? 0)}`;
    let id = welded.get(key);
    if (id === undefined) {
      id = welded.size;
      welded.set(key, id);
    }
    canonical[index] = id;
  }

  const edges = new Map<string, number>();
  for (let index = 0; index < indices.length; index += 3) {
    const a = canonical[indices[index] ?? -1];
    const b = canonical[indices[index + 1] ?? -1];
    const c = canonical[indices[index + 2] ?? -1];
    if (a === undefined || b === undefined || c === undefined || a === b || b === c || c === a) {
      throw new PipelineError("DEGENERATE_TRIANGLE", "Generated mesh contains an invalid triangle", false);
    }
    countEdge(edges, a, b);
    countEdge(edges, b, c);
    countEdge(edges, c, a);
  }
  if ([...edges.values()].some((count) => count !== 2)) {
    throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has open or non-manifold edges", false);
  }
}

function quantize(value: number): number {
  return Math.round(value * 100_000);
}

function countEdge(edges: Map<string, number>, left: number, right: number): void {
  const key = left < right ? `${left}:${right}` : `${right}:${left}`;
  edges.set(key, (edges.get(key) ?? 0) + 1);
}
