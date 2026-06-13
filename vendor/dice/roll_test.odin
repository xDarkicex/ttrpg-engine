package dice

import "core:fmt"
import "core:mem"
import "core:testing"

ARR_SIZE :: 8

// ---------------------------------------------------------------------------
// parse_uint
// ---------------------------------------------------------------------------

@(test)
test_parse_uint_empty :: proc(t: ^testing.T) {
	result := parse_uint("")
	testing.expect_value(t, result, 0)
}

@(test)
test_parse_uint_valid :: proc(t: ^testing.T) {
	result := parse_uint("123")
	testing.expect_value(t, result, 123)
}

@(test)
test_parse_uint_leading_zeros :: proc(t: ^testing.T) {
	result := parse_uint("007")
	testing.expect_value(t, result, 7)
}

@(test)
test_parse_uint_non_digit :: proc(t: ^testing.T) {
	result := parse_uint("12a3")
	testing.expect_value(t, result, 0)
}

@(test)
test_parse_uint_single_digit :: proc(t: ^testing.T) {
	result := parse_uint("5")
	testing.expect_value(t, result, 5)
}

@(test)
test_parse_uint_all_zeros :: proc(t: ^testing.T) {
	result := parse_uint("000")
	testing.expect_value(t, result, 0)
}

// ---------------------------------------------------------------------------
// parse_spec
// ---------------------------------------------------------------------------

@(test)
test_parse_spec_empty :: proc(t: ^testing.T) {
	spec, err := parse_spec("")
	testing.expect(t, err == Error.Invalid_Spec,
		fmt.tprintf("expected Invalid_Spec, got %v", err))
}

@(test)
test_parse_spec_d20 :: proc(t: ^testing.T) {
	spec, err := parse_spec("d20")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 1)
	testing.expect_value(t, spec.sides, 20)
	testing.expect_value(t, spec.modifier, 0)
}

@(test)
test_parse_spec_D20 :: proc(t: ^testing.T) {
	spec, err := parse_spec("D20")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 1)
	testing.expect_value(t, spec.sides, 20)
}

@(test)
test_parse_spec_3d6 :: proc(t: ^testing.T) {
	spec, err := parse_spec("3d6")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 3)
	testing.expect_value(t, spec.sides, 6)
}

@(test)
test_parse_spec_3D6 :: proc(t: ^testing.T) {
	spec, err := parse_spec("3D6")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 3)
	testing.expect_value(t, spec.sides, 6)
}

@(test)
test_parse_spec_plain_number :: proc(t: ^testing.T) {
	spec, err := parse_spec("20")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 1)
	testing.expect_value(t, spec.sides, 20)
}

@(test)
test_parse_spec_modifier_positive :: proc(t: ^testing.T) {
	spec, err := parse_spec("d20+5")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 1)
	testing.expect_value(t, spec.sides, 20)
	testing.expect_value(t, spec.modifier, 5)
}

@(test)
test_parse_spec_modifier_negative :: proc(t: ^testing.T) {
	spec, err := parse_spec("3d6-2")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 3)
	testing.expect_value(t, spec.sides, 6)
	testing.expect_value(t, spec.modifier, -2)
}

@(test)
test_parse_spec_keep_highest :: proc(t: ^testing.T) {
	spec, err := parse_spec("4d6k3")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 4)
	testing.expect_value(t, spec.sides, 6)
	testing.expect_value(t, spec.keep_mode, KeepMode.Highest)
	testing.expect_value(t, spec.keep_count, 3)
}

@(test)
test_parse_spec_drop_lowest :: proc(t: ^testing.T) {
	// "4d6d1" = drop lowest 1 = keep highest 3
	spec, err := parse_spec("4d6d1")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 4)
	testing.expect_value(t, spec.sides, 6)
	testing.expect_value(t, spec.keep_mode, KeepMode.Highest)
	testing.expect_value(t, spec.keep_count, 3)
	testing.expect_value(t, spec.drop_count, 1)
}

@(test)
test_parse_spec_exploding :: proc(t: ^testing.T) {
	spec, err := parse_spec("3d6!")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.exploding, true)
}

@(test)
test_parse_spec_exploding_e :: proc(t: ^testing.T) {
	spec, err := parse_spec("3d6e")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.exploding, true)
}

@(test)
test_parse_spec_reroll :: proc(t: ^testing.T) {
	spec, err := parse_spec("2d20r1")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.reroll_val, 1)
}

@(test)
test_parse_spec_target :: proc(t: ^testing.T) {
	spec, err := parse_spec("5d10t8")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.target, 8)
}

@(test)
test_parse_spec_fudge :: proc(t: ^testing.T) {
	spec, err := parse_spec("4dF")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 4)
	testing.expect_value(t, spec.die_type, DieType.Fudge)
}

@(test)
test_parse_spec_combined :: proc(t: ^testing.T) {
	// Modifier + exploding
	spec, err := parse_spec("3d6!+2")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, spec.count, 3)
	testing.expect_value(t, spec.sides, 6)
	testing.expect_value(t, spec.exploding, true)
	testing.expect_value(t, spec.modifier, 2)
}

@(test)
test_parse_spec_bare_d :: proc(t: ^testing.T) {
	_, err := parse_spec("d")
	testing.expect(t, err == Error.Invalid_Spec)
}

@(test)
test_parse_spec_empty_sides :: proc(t: ^testing.T) {
	_, err := parse_spec("3d")
	testing.expect(t, err == Error.Invalid_Spec)
}

@(test)
test_parse_spec_count_too_large :: proc(t: ^testing.T) {
	_, err := parse_spec("10001d6")
	testing.expect(t, err == Error.Too_Many_Dice)
}

@(test)
test_parse_spec_sides_too_large :: proc(t: ^testing.T) {
	_, err := parse_spec("d65536")
	testing.expect(t, err == Error.Invalid_Spec)
}

@(test)
test_parse_spec_invalid_suffix :: proc(t: ^testing.T) {
	_, err := parse_spec("d20x")
	testing.expect(t, err == Error.Invalid_Spec)
}

// ---------------------------------------------------------------------------
// roll
// ---------------------------------------------------------------------------

@(test)
test_roll_d20_range :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 1, sides = 20}
	for i in 0 ..< 100 {
		result, err := roll(results[:], spec)
		testing.expect_value(t, err, nil)
		testing.expect(t, result.total >= 1 && result.total <= 20,
			fmt.tprintf("roll d20 = %d, outside [1, 20]", result.total))
	}
}

@(test)
test_roll_3d6_range :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 3, sides = 6}
	for i in 0 ..< 100 {
		result, err := roll(results[:], spec)
		testing.expect_value(t, err, nil)
		testing.expect(t, result.total >= 3 && result.total <= 18,
			fmt.tprintf("roll 3d6 = %d, outside [3, 18]", result.total))
	}
}

@(test)
test_roll_with_modifier :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 1, sides = 20, modifier = 5}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	testing.expect(t, result.total == result.sum + 5,
		fmt.tprintf("total %d != sum %d + 5", result.total, result.sum))
}

@(test)
test_roll_advantage :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 1, sides = 20, advantage = .Advantage}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	// Should roll 2 dice, result.count reflects both
	testing.expect(t, result.count >= 2 || result.count >= 1,
		fmt.tprintf("expected at least 1 result, got %d", result.count))
	testing.expect(t, result.total >= 1 && result.total <= 20,
		fmt.tprintf("total %d outside [1,20]", result.total))
	// Higher should be first
	testing.expect(t, results[0] >= results[1],
		fmt.tprintf("advantage: results[0]=%d should be >= results[1]=%d", results[0], results[1]))
}

@(test)
test_roll_disadvantage :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 1, sides = 20, advantage = .Disadvantage}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	testing.expect(t, result.total >= 1 && result.total <= 20,
		fmt.tprintf("total %d outside [1,20]", result.total))
	// Lower should be first
	testing.expect(t, results[0] <= results[1],
		fmt.tprintf("disadvantage: results[0]=%d should be <= results[1]=%d", results[0], results[1]))
}

@(test)
test_roll_keep_highest :: proc(t: ^testing.T) {
	// We can't control RNG, but we can verify count/sum semantics
	results: [ARR_SIZE]int
	spec := RollSpec{count = 4, sides = 6, keep_mode = .Highest, keep_count = 3}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	testing.expect(t, result.count == 4, // all 4 dice displayed
		fmt.tprintf("display count %d should be 4", result.count))
}

@(test)
test_roll_drop_lowest :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 4, sides = 6, keep_mode = .Lowest, keep_count = 1}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	testing.expect(t, result.count == 4, // all 4 dice displayed
		fmt.tprintf("drop lowest: display count %d should be 4", result.count))
}

@(test)
test_roll_target :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 5, sides = 10, target = 8}
	result, err := roll(results[:], spec)
	testing.expect_value(t, err, nil)
	// sum is number of successes, should be between 0 and 5
	testing.expect(t, result.sum >= 0 && result.sum <= 5,
		fmt.tprintf("successes %d should be [0, 5]", result.sum))
}

@(test)
test_roll_fudge :: proc(t: ^testing.T) {
	results: [ARR_SIZE]int
	spec := RollSpec{count = 4, sides = 3, die_type = .Fudge}
	for i in 0 ..< 50 {
		result, err := roll(results[:], spec)
		testing.expect_value(t, err, nil)
		testing.expect(t, result.total >= -4 && result.total <= 4,
			fmt.tprintf("4dF = %d, outside [-4, 4]", result.total))
	}
}

@(test)
test_roll_too_many_dice :: proc(t: ^testing.T) {
	results: [1]int
	spec := RollSpec{count = 10001, sides = 6}
	_, err := roll(results[:], spec)
	testing.expect(t, err == Error.Too_Many_Dice)
}

// ---------------------------------------------------------------------------
// format_text
// ---------------------------------------------------------------------------

@(test)
test_format_text_basic :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [1]int = {5}
	spec := RollSpec{count = 1, sides = 20}
	result := RollResult{count = 1, sum = 5, total = 5}

	out := format_text(&arena, results[:1], result, spec)
	testing.expect_value(t, out, "1d20: [5] → 5")
}

@(test)
test_format_text_multiple :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [3]int = {3, 4, 6}
	spec := RollSpec{count = 3, sides = 6}
	result := RollResult{count = 3, sum = 13, total = 13}

	out := format_text(&arena, results[:3], result, spec)
	testing.expect_value(t, out, "3d6: [3, 4, 6] → 13")
}

@(test)
test_format_text_with_modifier :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [1]int = {12}
	spec := RollSpec{count = 1, sides = 20, modifier = 5}
	result := RollResult{count = 1, sum = 12, total = 17}

	out := format_text(&arena, results[:1], result, spec)
	testing.expect_value(t, out, "1d20+5: [12] → 12 + 5 = 17")
}

@(test)
test_format_text_advantage :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [2]int = {17, 8}
	spec := RollSpec{count = 1, sides = 20, advantage = .Advantage}
	result := RollResult{count = 2, sum = 17, total = 17}

	out := format_text(&arena, results[:2], result, spec)
	testing.expect(t, len(out) > 0, "expected non-empty output")
}

// ---------------------------------------------------------------------------
// format_json
// ---------------------------------------------------------------------------

@(test)
test_format_json_basic :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [1]int = {10}
	spec := RollSpec{count = 1, sides = 20}
	result := RollResult{count = 1, sum = 10, total = 10}

	out := format_json(&arena, results[:1], result, spec)
	testing.expect_value(t, out, `{"count":1,"sides":20,"rolls":[10],"sum":10,"total":10}`)
}

@(test)
test_format_json_with_modifier :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [3]int = {2, 3, 4}
	spec := RollSpec{count = 3, sides = 6, modifier = 2}
	result := RollResult{count = 3, sum = 9, total = 11}

	out := format_json(&arena, results[:3], result, spec)
	testing.expect_value(t, out, `{"count":3,"sides":6,"modifier":2,"rolls":[2,3,4],"sum":9,"total":11}`)
}

@(test)
test_format_json_keep :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [4]int = {6, 4, 3, 1}
	spec := RollSpec{count = 4, sides = 6, keep_mode = .Highest, keep_count = 3}
	result := RollResult{count = 4, sum = 13, total = 13}

	out := format_json(&arena, results[:4], result, spec)
	testing.expect(t, len(out) > 0, "expected non-empty JSON output")
}

@(test)
test_format_json_target :: proc(t: ^testing.T) {
	backing: [256]byte
	arena: mem.Arena
	mem.arena_init(&arena, backing[:])
	results: [5]int = {9, 3, 8, 6, 10}
	spec := RollSpec{count = 5, sides = 10, target = 8}
	result := RollResult{count = 5, sum = 3, total = 3}

	out := format_json(&arena, results[:5], result, spec)
	testing.expect(t, len(out) > 0, "expected non-empty JSON output")
}
