package dice

import "core:fmt"
import "core:mem"
import "core:strings"

/*
format_text writes a human-readable roll result.
Adapts output based on the roll spec's features.
*/
format_text :: proc(arena: ^mem.Arena, results: []int, result: RollResult, spec: RollSpec) -> string {
	b := strings.builder_make()

	spec_text(&b, spec)

	if spec.advantage != .None {
		strings.write_string(&b, ": [")
		adv_write_results(&b, results[:result.count], spec)
		strings.write_string(&b, "] → ")
		fmt.sbprintf(&b, "{}", result.total)
	} else if spec.exploding {
		strings.write_string(&b, ": [")
		write_comma_list(&b, results[:result.count])
		strings.write_string(&b, "] → ")
		fmt.sbprintf(&b, "{}", result.total)
	} else if spec.keep_mode != .All {
		strings.write_string(&b, ": [")
		write_comma_list(&b, results[:result.count])
		strings.write_string(&b, "] → ")
		fmt.sbprintf(&b, "{}", result.total)
	} else if spec.target > 0 {
		strings.write_string(&b, ": [")
		write_comma_list(&b, results[:result.count])
		fmt.sbprintf(&b, "] → {} successes", result.sum)
	} else if spec.modifier != 0 {
		strings.write_string(&b, ": [")
		write_comma_list(&b, results[:result.count])
		fmt.sbprintf(&b, "] → {} + {} = {}", result.sum, spec.modifier, result.total)
	} else {
		strings.write_string(&b, ": [")
		write_comma_list(&b, results[:result.count])
		fmt.sbprintf(&b, "] → {}", result.sum)
	}

	buf := strings.to_string(b)
	out, err := mem.arena_alloc_bytes(arena, len(buf))
	if err != nil do return ""
	copy(out, buf)
	return string(out)
}

/*
format_json writes a JSON roll result.
*/
format_json :: proc(arena: ^mem.Arena, results: []int, result: RollResult, spec: RollSpec) -> string {
	b := strings.builder_make()

	fmt.sbprintf(&b, `{{"count":{},"sides":{}`, spec.count, spec.sides)
	if spec.die_type == .Fudge {
		strings.write_string(&b, `,"type":"fudge"`)
	}
	if spec.modifier != 0 {
		fmt.sbprintf(&b, `,"modifier":{}`, spec.modifier)
	}
	if spec.advantage != .None {
		adv_str := spec.advantage == .Advantage ? "adv" : "disadv"
		fmt.sbprintf(&b, `,"advantage":"{}"`, adv_str)
	}
	if spec.keep_mode != .All {
		mode_str := spec.keep_mode == .Highest ? "highest" : "lowest"
		fmt.sbprintf(&b, `,"keep_mode":"{}","keep_count":{}`, mode_str, spec.keep_count)
		if spec.drop_count > 0 {
			fmt.sbprintf(&b, `,"drop_count":{}`, spec.drop_count)
		}
	}
	if spec.exploding {
		strings.write_string(&b, `,"exploding":true`)
	}
	if spec.reroll_val > 0 {
		fmt.sbprintf(&b, `,"reroll":{}`, spec.reroll_val)
	}
	if spec.target > 0 {
		fmt.sbprintf(&b, `,"target":{},"successes":{}`, spec.target, result.sum)
	}

	strings.write_string(&b, `,"rolls":[`)
	write_json_list(&b, results[:result.count])
	fmt.sbprintf(&b, `],"sum":{},"total":{}}}`, result.sum, result.total)

	buf := strings.to_string(b)
	out, err := mem.arena_alloc_bytes(arena, len(buf))
	if err != nil do return ""
	copy(out, buf)
	return string(out)
}

/*
spec_text writes the canonical dice notation string for a RollSpec.
*/
spec_text :: proc(b: ^strings.Builder, spec: RollSpec) {
	if spec.die_type == .Fudge {
		fmt.sbprintf(b, "{}dF", spec.count)
		return
	}
	fmt.sbprintf(b, "{}d{}", spec.count, spec.sides)
	if spec.modifier != 0 {
		if spec.modifier > 0 {
			fmt.sbprintf(b, "+{}", spec.modifier)
		} else {
			fmt.sbprintf(b, "-{}", -spec.modifier)
		}
	}
	if spec.drop_count > 0 {
		fmt.sbprintf(b, "d{}", spec.drop_count)
	} else if spec.keep_mode == .Highest {
		fmt.sbprintf(b, "k{}", spec.keep_count)
	} else if spec.keep_mode == .Lowest {
		fmt.sbprintf(b, "d{}", spec.keep_count)
	}
	if spec.exploding {
		strings.write_byte(b, '!')
	}
	if spec.reroll_val > 0 {
		fmt.sbprintf(b, "r{}", spec.reroll_val)
	}
	if spec.target > 0 {
		fmt.sbprintf(b, "t{}", spec.target)
	}
}

write_comma_list :: proc(b: ^strings.Builder, results: []int) {
	for i in 0 ..< len(results) {
		if i > 0 do strings.write_string(b, ", ")
		fmt.sbprintf(b, "{}", results[i])
	}
}

write_json_list :: proc(b: ^strings.Builder, results: []int) {
	for i in 0 ..< len(results) {
		if i > 0 do strings.write_byte(b, ',')
		fmt.sbprintf(b, "{}", results[i])
	}
}

adv_write_results :: proc(b: ^strings.Builder, results: []int, spec: RollSpec) {
	// For advantage/disadvantage: [used, discarded]
	if len(results) >= 2 {
		fmt.sbprintf(b, "{}, {}", results[0], results[1])
	}
}
