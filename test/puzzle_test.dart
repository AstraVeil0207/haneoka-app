import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:haneoka/games/puzzle_model.dart';

void main() {
  test('solves shuffled boards optimally enough to replay', () {
    final random = Random(7);
    for (final size in [3, 4]) {
      final goal = goalBoard(size);
      for (var round = 0; round < 5; round++) {
        final start = shuffleBoard(size, goal, size == 3 ? 40 : 30, random);
        final result = solvePuzzle(size, start, goal, 20000);
        expect(result.status, 'optimal');
        var board = start;
        for (final tile in result.path) {
          board = slide(size, board, tile)!;
        }
        expect(solved(board, goal), isTrue);
      }
    }
  });

  test('a known 3x3 board takes its optimal number of moves', () {
    // 8 6 7 / 2 5 4 / 3 _ 1 is one of the hardest: 31 moves.
    final result = solvePuzzle(3, [8, 6, 7, 2, 5, 4, 3, 0, 1], goalBoard(3), 60000);
    expect(result.status, 'optimal');
    expect(result.path.length, 31);
  });

  test('rejects unsolvable boards', () {
    final goal = goalBoard(3);
    final swapped = [...goal]..[0] = 2..[1] = 1;
    expect(solvePuzzle(3, swapped, goal, 1000).status, 'unsolvable');
  });
}
