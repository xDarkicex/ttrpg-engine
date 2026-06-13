package dice

import "core:fmt"
import "core:math"
import "core:testing"

@(test)
test_secure_uniform_int_n_equals_1 :: proc(t: ^testing.T) {
	// n=1 should always return 0
	for i in 0 ..< 100 {
		val := secure_uniform_int(1)
		testing.expect_value(t, val, 0)
	}
}

@(test)
test_secure_uniform_int_n_equals_2 :: proc(t: ^testing.T) {
	// n=2 should return 0 or 1
	for i in 0 ..< 100 {
		val := secure_uniform_int(2)
		testing.expect(t, val == 0 || val == 1,
			fmt.tprintf("secure_uniform_int(2) = %d, expected 0 or 1", val))
	}
}

@(test)
test_secure_uniform_int_power_of_two :: proc(t: ^testing.T) {
	// n=8 (2^3) should return 0-7
	for i in 0 ..< 100 {
		val := secure_uniform_int(8)
		testing.expect(t, val >= 0 && val < 8,
			fmt.tprintf("secure_uniform_int(8) = %d, expected [0, 7]", val))
	}
}

@(test)
test_secure_uniform_int_non_power_of_two :: proc(t: ^testing.T) {
	// n=6 is not a power of two - tests rejection sampling path
	for i in 0 ..< 100 {
		val := secure_uniform_int(6)
		testing.expect(t, val >= 0 && val < 6,
			fmt.tprintf("secure_uniform_int(6) = %d, expected [0, 5]", val))
	}
}

@(test)
test_secure_uniform_int_large :: proc(t: ^testing.T) {
	// n=10000
	for i in 0 ..< 100 {
		val := secure_uniform_int(10000)
		testing.expect(t, val >= 0 && val < 10000,
			fmt.tprintf("secure_uniform_int(10000) = %d, expected [0, 9999]", val))
	}
}

@(test)
test_secure_uniform_int_max_u32 :: proc(t: ^testing.T) {
	// n=max(u32) - largest power of 2
	val := secure_uniform_int(max(u32))
	testing.expect(t, val >= 0 && i64(val) < i64(max(u32)),
		fmt.tprintf("secure_uniform_int(max(u32)) = %d", val))
}

// Test that distribution is reasonably uniform (chi-squared test would be
// ideal, but we do a basic sanity check that no value is completely missing)
@(test)
test_secure_uniform_int_distribution :: proc(t: ^testing.T) {
	// Roll 2-sided dice 10000 times and verify both outcomes appear
	d1_count := 0
	d0_count := 0
	for i in 0 ..< 10000 {
		val := secure_uniform_int(2)
		if val == 0 {
			d0_count += 1
		} else if val == 1 {
			d1_count += 1
		}
	}
	// Each outcome should appear at least 100 times (0.1% threshold)
	testing.expect(t, d0_count > 100,
		fmt.tprintf("d0_count=%d, expected >100 (distribution check failed)", d0_count))
	testing.expect(t, d1_count > 100,
		fmt.tprintf("d1_count=%d, expected >100 (distribution check failed)", d1_count))
}
