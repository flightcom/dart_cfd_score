// Ported from `flatbush` (ISC License, © Vladimir Agafonkin) — packed Hilbert
// R-tree. Reduced to the subset used by `igc-xc-score`:
//   - constructor(numItems, [nodeSize])
//   - add(minX, minY, [maxX, maxY]) -> int
//   - finish()
//   - search(minX, minY, maxX, maxY) -> List<int>
//   - neighbors(x, y, [maxResults], [maxDistance]) -> List<int>
//
// Buffer serialization (`from(...)`) is intentionally omitted.

import 'dart:typed_data';

import 'package:collection/collection.dart';

class Flatbush {
  /// Allocate an index that will hold exactly [numItems] rectangles.
  /// [nodeSize] is the branching factor; clamped to [2, 65535] like upstream.
  Flatbush(this.numItems, [int nodeSize = 16])
      : assert(numItems > 0, 'numItems must be > 0'),
        nodeSize = nodeSize.clamp(2, 65535) {
    int n = numItems;
    int total = n;
    _levelBounds = <int>[n * 4];
    do {
      n = (n + this.nodeSize - 1) ~/ this.nodeSize;
      total += n;
      _levelBounds.add(total * 4);
    } while (n != 1);

    _boxes = Float64List(total * 4);
    _indices = total < 16384 ? Uint16List(total) : Uint32List(total);
    _pos = 0;
  }

  final int numItems;
  final int nodeSize;
  late final List<int> _levelBounds;
  late final Float64List _boxes;
  late final List<int> _indices; // Uint16List or Uint32List
  int _pos = 0;

  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  /// Add a rectangle. Single-point items can pass only `(x, y)` — the missing
  /// corners default to the same value, matching the upstream signature.
  int add(double minX, double minY, [double? maxX, double? maxY]) {
    final double mx = maxX ?? minX;
    final double my = maxY ?? minY;
    final int index = _pos >> 2;
    _indices[index] = index;
    _boxes[_pos++] = minX;
    _boxes[_pos++] = minY;
    _boxes[_pos++] = mx;
    _boxes[_pos++] = my;

    if (minX < this.minX) this.minX = minX;
    if (minY < this.minY) this.minY = minY;
    if (mx > this.maxX) this.maxX = mx;
    if (my > this.maxY) this.maxY = my;

    return index;
  }

  /// Build the index. Must be called after all `add` calls and before
  /// `search` / `neighbors`.
  void finish() {
    if (_pos >> 2 != numItems) {
      throw StateError('Added ${_pos >> 2} items when expected $numItems.');
    }
    if (numItems <= nodeSize) {
      _boxes[_pos++] = minX;
      _boxes[_pos++] = minY;
      _boxes[_pos++] = maxX;
      _boxes[_pos++] = maxY;
      return;
    }

    final double width = (maxX - minX) == 0 ? 1 : (maxX - minX);
    final double height = (maxY - minY) == 0 ? 1 : (maxY - minY);
    final Uint32List hilbertValues = Uint32List(numItems);
    const int hilbertMax = (1 << 16) - 1;

    for (int i = 0, pos = 0; i < numItems; i++) {
      final double iMinX = _boxes[pos++];
      final double iMinY = _boxes[pos++];
      final double iMaxX = _boxes[pos++];
      final double iMaxY = _boxes[pos++];
      final int x =
          (hilbertMax * ((iMinX + iMaxX) / 2 - minX) / width).floor();
      final int y =
          (hilbertMax * ((iMinY + iMaxY) / 2 - minY) / height).floor();
      hilbertValues[i] = _hilbert(x, y);
    }

    _sort(hilbertValues, _boxes, _indices, 0, numItems - 1, nodeSize);

    for (int i = 0, pos = 0; i < _levelBounds.length - 1; i++) {
      final int end = _levelBounds[i];
      while (pos < end) {
        final int nodeIndex = pos;
        double nodeMinX = _boxes[pos++];
        double nodeMinY = _boxes[pos++];
        double nodeMaxX = _boxes[pos++];
        double nodeMaxY = _boxes[pos++];
        for (int j = 1; j < nodeSize && pos < end; j++) {
          final double bx0 = _boxes[pos++];
          final double by0 = _boxes[pos++];
          final double bx1 = _boxes[pos++];
          final double by1 = _boxes[pos++];
          if (bx0 < nodeMinX) nodeMinX = bx0;
          if (by0 < nodeMinY) nodeMinY = by0;
          if (bx1 > nodeMaxX) nodeMaxX = bx1;
          if (by1 > nodeMaxY) nodeMaxY = by1;
        }
        _indices[_pos >> 2] = nodeIndex;
        _boxes[_pos++] = nodeMinX;
        _boxes[_pos++] = nodeMinY;
        _boxes[_pos++] = nodeMaxX;
        _boxes[_pos++] = nodeMaxY;
      }
    }
  }

  /// Indices of items whose bounding box intersects (or touches) the query.
  /// Optional [filter] is called with `(itemIndex, x0, y0, x1, y1)`.
  List<int> search(
    double minX,
    double minY,
    double maxX,
    double maxY, {
    bool Function(int index, double x0, double y0, double x1, double y1)? filter,
  }) {
    if (_pos != _boxes.length) {
      throw StateError('Data not yet indexed - call finish().');
    }

    int? nodeIndex = _boxes.length - 4;
    final List<int> queue = <int>[];
    final List<int> results = <int>[];
    final int leafBoundary = numItems * 4;

    while (nodeIndex != null) {
      final int end = _minInt(nodeIndex + nodeSize * 4,
          _upperBound(nodeIndex, _levelBounds));

      for (int pos = nodeIndex; pos < end; pos += 4) {
        final double x0 = _boxes[pos];
        if (maxX < x0) continue;
        final double y0 = _boxes[pos + 1];
        if (maxY < y0) continue;
        final double x1 = _boxes[pos + 2];
        if (minX > x1) continue;
        final double y1 = _boxes[pos + 3];
        if (minY > y1) continue;

        final int index = _indices[pos >> 2];

        if (nodeIndex >= leafBoundary) {
          queue.add(index);
        } else if (filter == null || filter(index, x0, y0, x1, y1)) {
          results.add(index);
        }
      }

      nodeIndex = queue.isNotEmpty ? queue.removeLast() : null;
    }

    return results;
  }

  /// Indices of items in order of distance from `(x, y)`. Caps at
  /// [maxResults] (default unlimited) and [maxDistance] (default unlimited).
  List<int> neighbors(
    double x,
    double y, {
    int maxResults = -1,
    double maxDistance = double.infinity,
    bool Function(int index)? filter,
  }) {
    if (_pos != _boxes.length) {
      throw StateError('Data not yet indexed - call finish().');
    }

    int? nodeIndex = _boxes.length - 4;
    final List<int> results = <int>[];
    final double maxDistSq = maxDistance * maxDistance;
    final int leafBoundary = numItems * 4;
    final HeapPriorityQueue<_QItem> q =
        HeapPriorityQueue<_QItem>((a, b) => a.dist.compareTo(b.dist));

    bool done = false;
    while (!done && nodeIndex != null) {
      final int end = _minInt(nodeIndex + nodeSize * 4,
          _upperBound(nodeIndex, _levelBounds));

      for (int pos = nodeIndex; pos < end; pos += 4) {
        final int index = _indices[pos >> 2];
        final double bMinX = _boxes[pos];
        final double bMinY = _boxes[pos + 1];
        final double bMaxX = _boxes[pos + 2];
        final double bMaxY = _boxes[pos + 3];
        final double dx = x < bMinX ? bMinX - x : (x > bMaxX ? x - bMaxX : 0);
        final double dy = y < bMinY ? bMinY - y : (y > bMaxY ? y - bMaxY : 0);
        final double dist = dx * dx + dy * dy;
        if (dist > maxDistSq) continue;

        final bool isLeaf = nodeIndex < leafBoundary;
        if (isLeaf) {
          if (filter == null || filter(index)) {
            q.add(_QItem(index, true, dist));
          }
        } else {
          q.add(_QItem(index, false, dist));
        }
      }

      // Drain leaves at the front of the queue (closest-first).
      while (q.isNotEmpty && q.first.isLeaf) {
        if (q.first.dist > maxDistSq) {
          done = true;
          break;
        }
        results.add(q.removeFirst().id);
        if (results.length == maxResults) {
          done = true;
          break;
        }
      }

      if (!done) {
        nodeIndex = q.isNotEmpty ? q.removeFirst().id : null;
      }
    }

    return results;
  }
}

class _QItem {
  const _QItem(this.id, this.isLeaf, this.dist);
  final int id;
  final bool isLeaf;
  final double dist;
}

int _minInt(int a, int b) => a < b ? a : b;

int _upperBound(int value, List<int> arr) {
  int i = 0;
  int j = arr.length - 1;
  while (i < j) {
    final int m = (i + j) >> 1;
    if (arr[m] > value) {
      j = m;
    } else {
      i = m + 1;
    }
  }
  return arr[i];
}

/// Custom quicksort over Hilbert values that keeps boxes/indices in sync.
/// Iterative (stack-based) to avoid Dart recursion limits on huge inputs.
void _sort(
  Uint32List values,
  Float64List boxes,
  List<int> indices,
  int left,
  int right,
  int nodeSize,
) {
  final List<int> stack = <int>[left, right];
  while (stack.isNotEmpty) {
    final int r = stack.removeLast();
    final int l = stack.removeLast();
    if (r - l <= nodeSize && (l ~/ nodeSize) >= (r ~/ nodeSize)) continue;

    final int a = values[l];
    final int b = values[(l + r) >> 1];
    final int c = values[r];
    final int pivot = ((a > b) != (a > c))
        ? a
        : ((b < a) != (b < c))
            ? b
            : c;

    int i = l - 1;
    int j = r + 1;
    while (true) {
      do {
        i++;
      } while (values[i] < pivot);
      do {
        j--;
      } while (values[j] > pivot);
      if (i >= j) break;
      _swap(values, boxes, indices, i, j);
    }

    stack.addAll(<int>[l, j, j + 1, r]);
  }
}

void _swap(
  Uint32List values,
  Float64List boxes,
  List<int> indices,
  int i,
  int j,
) {
  final int tmp = values[i];
  values[i] = values[j];
  values[j] = tmp;

  final int k = 4 * i;
  final int m = 4 * j;
  final double a = boxes[k];
  final double b = boxes[k + 1];
  final double c = boxes[k + 2];
  final double d = boxes[k + 3];
  boxes[k] = boxes[m];
  boxes[k + 1] = boxes[m + 1];
  boxes[k + 2] = boxes[m + 2];
  boxes[k + 3] = boxes[m + 3];
  boxes[m] = a;
  boxes[m + 1] = b;
  boxes[m + 2] = c;
  boxes[m + 3] = d;

  final int e = indices[i];
  indices[i] = indices[j];
  indices[j] = e;
}

/// Fast Hilbert curve algorithm by http://threadlocalmutex.com/
/// Ported from C++ https://github.com/rawrunprotected/hilbert_curves
/// (public domain). Inputs and outputs are unsigned 32-bit; we mask to
/// keep operations within that range despite Dart's 64-bit native ints.
int _hilbert(int xIn, int yIn) {
  const int mask32 = 0xFFFFFFFF;
  final int x = xIn & mask32;
  final int y = yIn & mask32;
  int a = (x ^ y) & mask32;
  int b = (0xFFFF ^ a) & mask32;
  int c = (0xFFFF ^ (x | y)) & mask32;
  int d = (x & (y ^ 0xFFFF)) & mask32;

  int A = (a | (b >> 1)) & mask32;
  int B = ((a >> 1) ^ a) & mask32;
  int C = (((c >> 1) ^ (b & (d >> 1))) ^ c) & mask32;
  int D = (((a & (c >> 1)) ^ (d >> 1)) ^ d) & mask32;

  a = A;
  b = B;
  c = C;
  d = D;
  A = ((a & (a >> 2)) ^ (b & (b >> 2))) & mask32;
  B = ((a & (b >> 2)) ^ (b & ((a ^ b) >> 2))) & mask32;
  C = (C ^ ((a & (c >> 2)) ^ (b & (d >> 2)))) & mask32;
  D = (D ^ ((b & (c >> 2)) ^ ((a ^ b) & (d >> 2)))) & mask32;

  a = A;
  b = B;
  c = C;
  d = D;
  A = ((a & (a >> 4)) ^ (b & (b >> 4))) & mask32;
  B = ((a & (b >> 4)) ^ (b & ((a ^ b) >> 4))) & mask32;
  C = (C ^ ((a & (c >> 4)) ^ (b & (d >> 4)))) & mask32;
  D = (D ^ ((b & (c >> 4)) ^ ((a ^ b) & (d >> 4)))) & mask32;

  a = A;
  b = B;
  c = C;
  d = D;
  C = (C ^ ((a & (c >> 8)) ^ (b & (d >> 8)))) & mask32;
  D = (D ^ ((b & (c >> 8)) ^ ((a ^ b) & (d >> 8)))) & mask32;

  a = (C ^ (C >> 1)) & mask32;
  b = (D ^ (D >> 1)) & mask32;

  int i0 = (xIn ^ yIn) & mask32;
  int i1 = (b | (0xFFFF ^ (i0 | a))) & mask32;

  i0 = (i0 | (i0 << 8)) & 0x00FF00FF;
  i0 = (i0 | (i0 << 4)) & 0x0F0F0F0F;
  i0 = (i0 | (i0 << 2)) & 0x33333333;
  i0 = (i0 | (i0 << 1)) & 0x55555555;

  i1 = (i1 | (i1 << 8)) & 0x00FF00FF;
  i1 = (i1 | (i1 << 4)) & 0x0F0F0F0F;
  i1 = (i1 | (i1 << 2)) & 0x33333333;
  i1 = (i1 | (i1 << 1)) & 0x55555555;

  return ((i1 << 1) | i0) & mask32;
}
