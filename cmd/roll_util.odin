package cmd

import dice "ext:dice"

/*
resolve_amount parses a dice spec like "2d6+3", "8d6", "4d8+5" and returns
the rolled total.
*/
resolve_amount :: proc(s: string) -> (int, bool) {
	spec, err := dice.parse_spec(s)
	if err != nil {
		return 0, false
	}
	results: [dice.MAX_DICE]int
	result, roll_err := dice.roll(results[:], spec)
	if roll_err != nil {
		return 0, false
	}
	return result.total, true
}

/*
resolve_d20 parses a d20 roll spec (e.g. "d20", "d20+5", "d20+5 --adv").
Returns the raw d20 roll, the total with modifier, and any advantage mode.
*/
resolve_d20 :: proc(s: string) -> (roll: int, total: int, advantage: dice.Advantage, ok: bool) {
	spec, err := dice.parse_spec(s)
	if err != nil {
		return 0, 0, .None, false
	}

	if spec.count < 1 {
		spec.count = 1
	}
	if spec.sides < 1 {
		spec.sides = 20
	}

	results: [dice.MAX_DICE]int
	result, roll_err := dice.roll(results[:], spec)
	if roll_err != nil {
		return 0, 0, .None, false
	}

	return result.sum, result.total, spec.advantage, true
}

/*
roll_d20 is a convenience proc that rolls a flat 1d20.
*/
roll_d20 :: proc() -> int {
	spec := dice.RollSpec{count = 1, sides = 20}
	results: [2]int
	result, _ := dice.roll(results[:], spec)
	return result.total
}

/*
roll_initiative parses an initiative spec like "1d20+3" and returns
the total initiative score.
*/
roll_initiative :: proc(s: string) -> (int, bool) {
	spec, err := dice.parse_spec(s)
	if err != nil {
		return 0, false
	}
	if spec.count < 1 {
		spec.count = 1
	}
	if spec.sides < 1 {
		spec.sides = 20
	}
	results: [dice.MAX_DICE]int
	result, roll_err := dice.roll(results[:], spec)
	if roll_err != nil {
		return 0, false
	}
	return result.total, true
}

/*
roll_hit_dice rolls hit dice for short rest healing.
Returns the total HP healed.
*/
roll_hit_dice :: proc(hit_die: int, count: int, con_mod: int) -> (total: int, ok: bool) {
	if count < 1 || hit_die < 1 {
		return 0, false
	}
	spec := dice.RollSpec{count = count, sides = hit_die, modifier = con_mod * count}
	results: [dice.MAX_DICE]int
	result, err := dice.roll(results[:], spec)
	if err != nil {
		return 0, false
	}
	return result.total, true
}

/*
is_rollable returns true if the string looks like a dice spec (contains 'd')
or a plain number. Used to distinguish attack rolls from save ability names.
*/
is_rollable :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == 'd' || c == 'D' {
			return true
		}
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

/*
resolve_attack_roll parses an attack roll spec. Returns the total roll value.
Handles "18", "d20", "d20+5", etc.
*/
resolve_attack_roll :: proc(s: string) -> (int, bool) {
	if len(s) == 0 {
		return 0, false
	}
	spec, err := dice.parse_spec(s)
	if err != nil {
		return 0, false
	}
	if spec.count < 1 {
		spec.count = 1
	}
	if spec.sides < 1 {
		spec.sides = 20
	}
	results: [dice.MAX_DICE]int
	result, roll_err := dice.roll(results[:], spec)
	if roll_err != nil {
		return 0, false
	}
	return result.total, true
}

/*
resolve_save_roll parses a saving throw roll spec. Returns the total.
*/
resolve_save_roll :: proc(s: string) -> (int, bool) {
	if len(s) == 0 {
		return 0, false
	}
	spec, err := dice.parse_spec(s)
	if err != nil {
		return 0, false
	}
	if spec.count < 1 {
		spec.count = 1
	}
	if spec.sides < 1 {
		spec.sides = 20
	}
	results: [dice.MAX_DICE]int
	result, roll_err := dice.roll(results[:], spec)
	if roll_err != nil {
		return 0, false
	}
	return result.total, true
}
