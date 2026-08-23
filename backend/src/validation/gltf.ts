import { NodeIO, Primitive, PropertyType, type TypedArray, type TypedArrayConstructor } from "@gltf-transform/core";
import { compactPrimitive, dedup, flatten, join, weldPrimitive } from "@gltf-transform/functions";
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

const MAX_REPAIR_BOUNDARY_LOOPS = 16;
const MAX_REPAIR_BOUNDARY_VERTICES = 768;

type CanonicalPositions = {
  canonical: number[];
  representatives: Map<number, number>;
};

type EdgeRecord = {
  count: number;
  from: number;
  to: number;
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
    sanitizeAndRepairPrimitive(primitive);
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

function sanitizeAndRepairPrimitive(primitive: Primitive): void {
  if (primitive.listTargets().length > 0 || primitive.listSemantics().some((semantic) => /^JOINTS_|^WEIGHTS_/.test(semantic))) {
    throw new PipelineError("RIGGED_MODEL", "Rigid accessories cannot contain skinning or morph-target data", false);
  }
  if (!primitive.getIndices()) weldPrimitive(primitive, { overwrite: true });

  let position = primitive.getAttribute("POSITION");
  let positions = position?.getArray();
  const indexAccessor = primitive.getIndices();
  const rawIndices = indexAccessor?.getArray();
  if (!position || !positions) {
    throw new PipelineError("MISSING_POSITIONS", "Generated mesh has no positions", false);
  }
  if (!indexAccessor || !rawIndices) {
    throw new PipelineError("INVALID_TRIANGLES", "Generated mesh could not be indexed", false);
  }

  const vertexCount = position.getCount();
  const { canonical } = canonicalizePositions(positions);
  const sanitizedIndices: number[] = [];
  const triangles = new Set<string>();
  for (let offset = 0; offset + 2 < rawIndices.length; offset += 3) {
    const a = Number(rawIndices[offset]);
    const b = Number(rawIndices[offset + 1]);
    const c = Number(rawIndices[offset + 2]);
    if (
      !Number.isInteger(a) ||
      !Number.isInteger(b) ||
      !Number.isInteger(c) ||
      a < 0 ||
      b < 0 ||
      c < 0 ||
      a >= vertexCount ||
      b >= vertexCount ||
      c >= vertexCount
    ) {
      throw new PipelineError("INVALID_TRIANGLES", "Generated mesh contains an out-of-range triangle index", false);
    }
    const ca = canonical[a];
    const cb = canonical[b];
    const cc = canonical[c];
    if (ca === undefined || cb === undefined || cc === undefined || ca === cb || cb === cc || cc === ca) continue;
    if (triangleAreaSquared(positions, a, b, c) <= 1e-18) continue;
    const key = [ca, cb, cc].sort((left, right) => left - right).join(":");
    if (triangles.has(key)) continue;
    triangles.add(key);
    sanitizedIndices.push(a, b, c);
  }
  if (sanitizedIndices.length === 0) {
    throw new PipelineError("EMPTY_MESH", "Generated mesh contains no usable geometry", false);
  }
  indexAccessor.setArray(indexArray(sanitizedIndices));

  // Provider meshes occasionally retain unused vertices after remeshing. They
  // count against Roblox's upload budget even though no face references them.
  compactPrimitive(primitive);
  position = primitive.getAttribute("POSITION");
  positions = position?.getArray();
  const compactIndices = primitive.getIndices()?.getArray();
  if (!position || !positions || !compactIndices) {
    throw new PipelineError("INVALID_TRIANGLES", "Generated mesh could not be compacted", false);
  }

  const topology = collectTopology(positions, compactIndices);
  if (topology.nonManifold) {
    throw new PipelineError("NOT_WATERTIGHT", "Generated mesh contains non-manifold edges", false);
  }
  if (topology.boundaryEdges.length === 0) return;

  const loops = buildBoundaryLoops(topology.boundaryEdges);
  const boundaryVertexCount = loops.reduce((total, loop) => total + loop.length, 0);
  if (loops.length > MAX_REPAIR_BOUNDARY_LOOPS || boundaryVertexCount > MAX_REPAIR_BOUNDARY_VERTICES) {
    throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has too many open boundaries to repair safely", false);
  }

  const centerLoops = loops.filter((loop) => loop.length > 3);
  const centerIndices = appendLoopCenters(primitive, centerLoops, topology.representatives);
  const repairedIndices = Array.from(compactIndices, Number);
  let centerCursor = 0;
  for (const loop of loops) {
    if (loop.length === 3) {
      repairedIndices.push(
        requiredRepresentative(topology.representatives, loop[1]),
        requiredRepresentative(topology.representatives, loop[0]),
        requiredRepresentative(topology.representatives, loop[2]),
      );
      continue;
    }
    const center = centerIndices[centerCursor];
    centerCursor += 1;
    if (center === undefined) {
      throw new PipelineError("MESH_REPAIR_FAILED", "Generated mesh repair lost a boundary center", false);
    }
    for (let index = 0; index < loop.length; index += 1) {
      const left = loop[index];
      const right = loop[(index + 1) % loop.length];
      if (left === undefined || right === undefined) continue;
      repairedIndices.push(
        requiredRepresentative(topology.representatives, right),
        requiredRepresentative(topology.representatives, left),
        center,
      );
    }
  }
  primitive.getIndices()?.setArray(indexArray(repairedIndices));

  const repairedPosition = primitive.getAttribute("POSITION")?.getArray();
  const finalIndices = primitive.getIndices()?.getArray();
  if (!repairedPosition || !finalIndices) {
    throw new PipelineError("MESH_REPAIR_FAILED", "Generated mesh repair produced no geometry", false);
  }
  assertWatertight(repairedPosition, finalIndices);
}

function triangleAreaSquared(positions: ArrayLike<number>, a: number, b: number, c: number): number {
  const ax = positions[a * 3] ?? 0;
  const ay = positions[a * 3 + 1] ?? 0;
  const az = positions[a * 3 + 2] ?? 0;
  const abx = (positions[b * 3] ?? 0) - ax;
  const aby = (positions[b * 3 + 1] ?? 0) - ay;
  const abz = (positions[b * 3 + 2] ?? 0) - az;
  const acx = (positions[c * 3] ?? 0) - ax;
  const acy = (positions[c * 3 + 1] ?? 0) - ay;
  const acz = (positions[c * 3 + 2] ?? 0) - az;
  const crossX = aby * acz - abz * acy;
  const crossY = abz * acx - abx * acz;
  const crossZ = abx * acy - aby * acx;
  return crossX * crossX + crossY * crossY + crossZ * crossZ;
}

function collectTopology(positions: ArrayLike<number>, indices: ArrayLike<number>): {
  boundaryEdges: EdgeRecord[];
  representatives: Map<number, number>;
  nonManifold: boolean;
} {
  const { canonical, representatives } = canonicalizePositions(positions);
  const edges = new Map<string, EdgeRecord>();
  for (let offset = 0; offset + 2 < indices.length; offset += 3) {
    const a = canonical[Number(indices[offset])];
    const b = canonical[Number(indices[offset + 1])];
    const c = canonical[Number(indices[offset + 2])];
    if (a === undefined || b === undefined || c === undefined) {
      throw new PipelineError("INVALID_TRIANGLES", "Generated mesh contains an invalid triangle", false);
    }
    collectEdge(edges, a, b);
    collectEdge(edges, b, c);
    collectEdge(edges, c, a);
  }
  return {
    boundaryEdges: [...edges.values()].filter((edge) => edge.count === 1),
    representatives,
    nonManifold: [...edges.values()].some((edge) => edge.count > 2),
  };
}

function collectEdge(edges: Map<string, EdgeRecord>, from: number, to: number): void {
  const key = edgeKey(from, to);
  const edge = edges.get(key);
  if (edge) edge.count += 1;
  else edges.set(key, { count: 1, from, to });
}

function buildBoundaryLoops(boundaryEdges: EdgeRecord[]): number[][] {
  const adjacency = new Map<number, number[]>();
  const unused = new Set<string>();
  const records = new Map<string, EdgeRecord>();
  for (const edge of boundaryEdges) {
    const key = edgeKey(edge.from, edge.to);
    unused.add(key);
    records.set(key, edge);
    adjacency.set(edge.from, [...(adjacency.get(edge.from) ?? []), edge.to]);
    adjacency.set(edge.to, [...(adjacency.get(edge.to) ?? []), edge.from]);
  }
  if ([...adjacency.values()].some((neighbors) => neighbors.length !== 2)) {
    throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has branching open boundaries", false);
  }

  const loops: number[][] = [];
  while (unused.size > 0) {
    const firstKey = unused.values().next().value as string | undefined;
    const first = firstKey ? records.get(firstKey) : undefined;
    if (!first || !firstKey) break;
    unused.delete(firstKey);
    const loop = [first.from, first.to];
    let previous = first.from;
    let current = first.to;
    while (current !== loop[0]) {
      const neighbors = adjacency.get(current);
      if (!neighbors) {
        throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has an incomplete open boundary", false);
      }
      const next = neighbors[0] === previous ? neighbors[1] : neighbors[0];
      if (next === undefined) {
        throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has an incomplete open boundary", false);
      }
      const nextKey = edgeKey(current, next);
      if (!unused.has(nextKey)) {
        throw new PipelineError("NOT_WATERTIGHT", "Generated mesh boundary could not be repaired safely", false);
      }
      unused.delete(nextKey);
      previous = current;
      current = next;
      if (current !== loop[0]) loop.push(current);
      if (loop.length > MAX_REPAIR_BOUNDARY_VERTICES) {
        throw new PipelineError("NOT_WATERTIGHT", "Generated mesh boundary is too large to repair safely", false);
      }
    }
    if (loop.length < 3) {
      throw new PipelineError("NOT_WATERTIGHT", "Generated mesh has an invalid open boundary", false);
    }
    loops.push(loop);
  }
  return loops;
}

function appendLoopCenters(
  primitive: Primitive,
  loops: number[][],
  representatives: Map<number, number>,
): number[] {
  if (loops.length === 0) return [];
  const originalCount = primitive.getAttribute("POSITION")?.getCount() ?? 0;
  for (const accessor of primitive.listAttributes()) {
    const source = accessor.getArray();
    if (!source) continue;
    const elementSize = accessor.getElementSize();
    const Constructor = source.constructor as TypedArrayConstructor;
    const expanded = new Constructor(source.length + loops.length * elementSize) as TypedArray;
    expanded.set(source);
    for (let loopIndex = 0; loopIndex < loops.length; loopIndex += 1) {
      const loop = loops[loopIndex];
      if (!loop) continue;
      for (let component = 0; component < elementSize; component += 1) {
        let total = 0;
        for (const canonicalIndex of loop) {
          const representative = requiredRepresentative(representatives, canonicalIndex);
          total += Number(source[representative * elementSize + component] ?? 0);
        }
        expanded[source.length + loopIndex * elementSize + component] = total / loop.length;
      }
    }
    accessor.setArray(expanded);
  }
  return loops.map((_, index) => originalCount + index);
}

function canonicalizePositions(positions: ArrayLike<number>): CanonicalPositions {
  const vertexCount = Math.floor(positions.length / 3);
  const welded = new Map<string, number>();
  const representatives = new Map<number, number>();
  const canonical = new Array<number>(vertexCount);
  for (let index = 0; index < vertexCount; index += 1) {
    const offset = index * 3;
    const key = `${quantize(positions[offset] ?? 0)},${quantize(positions[offset + 1] ?? 0)},${quantize(positions[offset + 2] ?? 0)}`;
    let id = welded.get(key);
    if (id === undefined) {
      id = welded.size;
      welded.set(key, id);
      representatives.set(id, index);
    }
    canonical[index] = id;
  }
  return { canonical, representatives };
}

function requiredRepresentative(representatives: Map<number, number>, canonicalIndex: number | undefined): number {
  const representative = canonicalIndex === undefined ? undefined : representatives.get(canonicalIndex);
  if (representative === undefined) {
    throw new PipelineError("MESH_REPAIR_FAILED", "Generated mesh repair lost a boundary vertex", false);
  }
  return representative;
}

function indexArray(indices: number[]): TypedArray {
  const maximum = indices.reduce((current, value) => Math.max(current, value), 0);
  return (maximum <= 65_535 ? new Uint16Array(indices) : new Uint32Array(indices)) as TypedArray;
}

function edgeKey(left: number, right: number): string {
  return left < right ? `${left}:${right}` : `${right}:${left}`;
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
  const { canonical } = canonicalizePositions(positions);

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
