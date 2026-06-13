package dice

import "core:c"

when ODIN_OS == .Darwin {
	foreign import libc "system:System"
} else {
	foreign import libc "system:c"
}

when ODIN_OS == .Linux {
	foreign libc {
		@(link_name = "getrandom")
		syscall_getrandom :: proc(buf: rawptr, buflen: u64, flags: u32) -> i64 ---
	}
}

when ODIN_OS == .Darwin {
	foreign libc {
		@(link_name = "arc4random_uniform")
		syscall_arc4random_uniform :: proc(upper_bound: u32) -> u32 ---
	}
}

// secure_uniform_int returns a cryptographically uniform integer
// in [0, n). Returns -1 on any internal failure.
secure_uniform_int :: proc(n: u32) -> i64 {
	when ODIN_OS == .Darwin {
		return i64(syscall_arc4random_uniform(n))
	}
	when ODIN_OS == .Linux {
		GRND_NONBLOCK :: 0x0002
		buf: u32
		nread := syscall_getrandom(&buf, size_of(buf), GRND_NONBLOCK)
		if nread != 4 {
			return -1
		}
		if n & (n - 1) == 0 {
			return i64(buf) % i64(n)
		}
		limit := (max(u32) / n) * n
		for buf >= limit {
			nread = syscall_getrandom(&buf, size_of(buf), GRND_NONBLOCK)
			if nread != 4 {
				return -1
			}
		}
		return i64(buf) % i64(n)
	}
	return -1
}
