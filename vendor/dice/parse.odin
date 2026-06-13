package dice

import "core:strconv"
import "core:strings"

/*
parse_spec parses a complete dice expression.
Accepts: d20, 3d6, d20+5, 3d6-2, 4d6k3, 4d6d1, 3d6!, 2d20r1, 5d10t8, 4dF
*/
parse_spec :: proc(spec: string) -> (RollSpec, Error) {
	if len(spec) == 0 {
		return {}, Error.Invalid_Spec
	}

	rs := RollSpec{}

	d_pos, has_d := find_d(spec)
	if !has_d {
		// Plain number: "20" → 1d20
		sides := parse_uint(spec)
		if sides < 1 || sides > MAX_SIDES {
			return {}, Error.Invalid_Spec
		}
		rs.count = 1
		rs.sides = sides
		return rs, nil
	}

	// Parse count before 'd'
	if d_pos == 0 {
		rs.count = 1
	} else {
		rs.count = parse_uint(spec[:d_pos])
		if rs.count < 1 || rs.count > MAX_DICE {
			return {}, Error.Too_Many_Dice
		}
	}

	suffix_start := parse_sides(spec, d_pos, &rs)
	if suffix_start < 0 {
		return {}, Error.Invalid_Spec
	}

	if suffix_start < len(spec) {
		if err := parse_suffixes(spec[suffix_start:], &rs); err != nil {
			return {}, err
		}
	}

	return rs, nil
}

/*
find_d locates the 'd' or 'D' separator in a dice spec.
Returns -1 if not found.
*/
find_d :: proc(spec: string) -> (pos: int, found: bool) {
	for i := 0; i < len(spec); i += 1 {
		if spec[i] == 'd' || spec[i] == 'D' {
			return i, true
		}
	}
	return -1, false
}

/*
parse_sides extracts the sides value after 'd'.
Returns the position after the sides number, or -1 on error.
*/
parse_sides :: proc(spec: string, d_pos: int, rs: ^RollSpec) -> int {
	rest := spec[d_pos+1:]
	if len(rest) == 0 {
		return -1
	}

	if rest[0] == 'f' || rest[0] == 'F' {
		rs.die_type = .Fudge
		rs.sides = 3
		return d_pos + 2
	}

	end := 0
	for end < len(rest) {
		c := rest[end]
		if c < '0' || c > '9' {
			break
		}
		end += 1
	}

	if end == 0 {
		return -1
	}

	rs.sides = parse_uint(rest[:end])
	if rs.sides < 1 || rs.sides > MAX_SIDES {
		return -1
	}

	return d_pos + 1 + end
}

/*
parse_suffixes handles modifier, keep/drop, exploding, reroll, target.
Each suffix is optional and parsed in order.
*/
parse_suffixes :: proc(s: string, rs: ^RollSpec) -> Error {
	i := 0
	for i < len(s) {
		c := s[i]

		if c == '+' || c == '-' {
			if rs.modifier != 0 {
				return Error.Invalid_Spec
			}
			val, consumed := parse_optional_int(s[i:])
			if consumed == 0 {
				return Error.Invalid_Spec
			}
			rs.modifier = val
			i += consumed
		} else if c == 'd' {
			val, consumed := parse_optional_int(s[i+1:])
			if consumed == 0 || val < 1 || val >= rs.count {
				return Error.Invalid_Spec
			}
			// "drop lowest N" = keep highest (count - N)
			rs.keep_mode = .Highest
			rs.keep_count = rs.count - val
			rs.drop_count = val
			i += 1 + consumed
		} else if c == 'k' {
			val, consumed := parse_optional_int(s[i+1:])
			if consumed == 0 || val < 1 {
				return Error.Invalid_Spec
			}
			rs.keep_mode = .Highest
			rs.keep_count = val
			i += 1 + consumed
		} else if c == '!' || c == 'e' {
			rs.exploding = true
			i += 1
		} else if c == 'r' {
			val, consumed := parse_optional_int(s[i+1:])
			if consumed == 0 || val < 1 {
				return Error.Invalid_Spec
			}
			rs.reroll_val = val
			i += 1 + consumed
		} else if c == 't' {
			val, consumed := parse_optional_int(s[i+1:])
			if consumed == 0 || val < 1 {
				return Error.Invalid_Spec
			}
			rs.target = val
			i += 1 + consumed
		} else {
			return Error.Invalid_Spec
		}
	}
	return nil
}

/*
parse_optional_int parses an optional signed or unsigned integer.
Returns the parsed value and number of bytes consumed.
For "+5": returns 5, 2. For "-3": returns -3, 2. For "3": returns 3, 1.
*/
parse_optional_int :: proc(s: string) -> (value: int, consumed: int) {
	if len(s) == 0 do return 0, 0

	neg := 1
	pos := 0

	if s[pos] == '+' {
		pos += 1
	} else if s[pos] == '-' {
		neg = -1
		pos += 1
	}

	if pos >= len(s) do return 0, 0

	start := pos
	for pos < len(s) {
		c := s[pos]
		if c < '0' || c > '9' {
			break
		}
		pos += 1
	}

	if pos == start do return 0, 0

	return neg * parse_uint(s[start:pos]), pos
}

/*
parse_uint parses a decimal string to int. Returns 0 on failure.
*/
parse_uint :: proc(s: string) -> int {
	result := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c < '0' || c > '9' {
			return 0
		}
		result = result * 10 + int(c - '0')
	}
	return result
}
