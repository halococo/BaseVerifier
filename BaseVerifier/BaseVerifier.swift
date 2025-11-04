//
//  BaseVerifier.swift
//  BaseVerifier
//
//  Created by Byul Kang
//  Core engine: 64-bit deterministic Miller–Rabin, safe 128-bit mul via fullWidth
//

import Foundation
import Combine

// Thread-safe boolean box for worker threads (no actor crossing)
final class StopBox: @unchecked Sendable {
    private var _value: Bool = false
    private let lock = NSLock()
    func set(_ v: Bool) { lock.lock(); _value = v; lock.unlock() }
    func get() -> Bool { lock.lock(); let v = _value; lock.unlock(); return v }
}

final class BaseVerifier: ObservableObject {

    // MARK: - Published UI state
    @Published var progress: Double = 0.0
    @Published var primesChecked: UInt64 = 0
    @Published var statusLine: String = "Idle"
    @Published var isRunning: Bool = false
    @Published var violationFound: Bool = false
    @Published var logLines: [String] = []

    // MARK: - Control
    private var task: Task<Void, Never>? = nil
    private let stopBox = StopBox()

    // UI update cadence (batch size for throttling MainActor updates)
    private let stepBatch: UInt64 = 8_192

    /// Thread-safe log appender; always executes on the main actor.
    func appendLog(_ s: String) {
        Task { @MainActor in
            self.logLines.append(s)
            if self.logLines.count > 200 {
                self.logLines.removeFirst(self.logLines.count - 200)
            }
        }
    }

    /// Backward-compatible entry point (lower defaults to 2)
    func start(base: UInt64, limit: UInt64, threads: Int) {
        start(base: base, startFrom: 2, limit: limit, threads: threads)
    }

    /// Range-aware entry point
    func start(base: UInt64, startFrom: UInt64, limit: UInt64, threads: Int) {
        stop() // clean up previous
        progress = 0
        primesChecked = 0
        statusLine = "Running..."
        violationFound = false
        isRunning = true
        stopBox.set(false)
        appendLog("🚀 Start: base=\(base), range=\(startFrom.formatted())...\(limit.formatted()), threads=\(threads > 0 ? threads : -1)")

        task = Task { await run(base: base, startFrom: startFrom, limit: limit, threads: threads) }
    }

    func stop() {
        stopBox.set(true)
        task?.cancel()
        task = nil
    }

    private func run(base: UInt64, startFrom: UInt64, limit: UInt64, threads: Int) async {
        // Guard against invalid ranges
        guard startFrom <= limit else {
            await MainActor.run { self.statusLine = "⚠️ Invalid range: start > limit" }
            return
        }

        let started = Date()
        let t = threads > 0 ? threads : max(1, ProcessInfo.processInfo.activeProcessorCount)
        let totalRange = limit - startFrom + 1
        let chunk = max<UInt64>(1, totalRange / UInt64(t))

        // shared counters (protected by lock)
        var globalProcessed: UInt64 = 0
        var globalPrimes: UInt64 = 0
        var lastProgress: Double = 0
        let lock = NSLock()

        // first violation (if any)
        struct Hit { let p: UInt64; let s: UInt64; let fac: String }
        var first: Hit? = nil

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<t {
                let start = startFrom + UInt64(i) * chunk
                let end   = (i == t - 1) ? limit : (startFrom + UInt64(i + 1) * chunk - 1)

                group.addTask { [stepBatch, stopBox] in
                    var processed: UInt64 = 0
                    var localPrimes: UInt64 = 0
                    var n = start

                    // Handle 2 once, then scan odd numbers only for speed
                    if n <= 2 && 2 <= end {
                        if Math.isPrime64(2) {
                            localPrimes &+= 1
                            let s = Math.digitSum(2, base: base)
                            if !Math.isValidDigitSum(s) {
                                let fac = Math.factorizationString(of: s)
                                lock.lock(); if first == nil { first = Hit(p: 2, s: s, fac: fac) }; lock.unlock()
                            }
                        }
                        processed &+= 1 // count '2' in progress
                        n = max(n, 3)
                    }
                    if n % 2 == 0 { n &+= 1 }

                    while n <= end {
                        if Task.isCancelled || stopBox.get() { break }

                        if Math.isPrime64(n) {
                            localPrimes &+= 1
                            let s = Math.digitSum(n, base: base)
                            if !Math.isValidDigitSum(s) {
                                let fac = Math.factorizationString(of: s)
                                lock.lock()
                                if first == nil { first = Hit(p: n, s: s, fac: fac) }
                                lock.unlock()
                                break
                            }
                        }

                        // Advance by two (odd-only). Simpler and clearer.
                        processed &+= 2
                        n &+= 2
                        if n > end {
                            let overshoot = n &- end &- 1
                            if overshoot > 0 { processed &-= overshoot }
                        }

                        if (processed % stepBatch) == 0 || n > end {
                            lock.lock()
                            globalProcessed &+= processed
                            globalPrimes &+= localPrimes
                            let raw = min(1.0, Double(globalProcessed) / Double(max(1, totalRange)))
                            if raw > lastProgress { lastProgress = raw }
                            let prog = lastProgress
                            let primesNow = globalPrimes
                            lock.unlock()

                            processed = 0
                            localPrimes = 0

                            await MainActor.run {
                                self.progress = prog
                                self.primesChecked = primesNow
                            }
                        }
                    }
                }
            }
            await group.waitForAll()
        }

        let elapsed = Date().timeIntervalSince(started)

        await MainActor.run {
            self.isRunning = false
            self.progress = 1.0
        }

        if stopBox.get() {
            await MainActor.run {
                self.statusLine = "Stopped."
                self.appendLog("Stopped.")
            }
            return
        }

        if let v = first {
            await MainActor.run {
                self.violationFound = true
                self.statusLine = "❌ Violation: p=\(v.p)  S(p)=\(v.s)  (\(v.fac))"
                self.appendLog(self.statusLine)
            }
        } else {
            await MainActor.run {
                self.violationFound = false
                self.statusLine = "✅ No violations found in range \(startFrom.formatted())...\(limit.formatted())."
                self.appendLog("Done in \(String(format: "%.2f", elapsed)) s – primes: \(self.primesChecked.formatted())")
            }
        }
    }
}

// MARK: - Math helpers
enum Math {

    static func digitSum(_ n: UInt64, base: UInt64) -> UInt64 {
        var x = n, s: UInt64 = 0
        while x > 0 { s &+= x % base; x /= base }
        return s
    }

    static func isValidDigitSum(_ n: UInt64) -> Bool {
        if n == 1 { return true }
        if isPrime64(n) { return true }
        if isSemiprimeDistinct(n) { return true }
        if isPrimePower(n) { return true }
        return false
    }

    static func isSemiprimeDistinct(_ n: UInt64) -> Bool {
        if n < 6 { return false }
        var m = n
        var first: UInt64? = nil
        var f: UInt64 = 2
        while f * f <= m {
            if m % f == 0 {
                if first == nil { first = f }
                else {
                    if first! == f { return false }
                    else { m /= f; return m == 1 }
                }
                m /= f
                while m % f == 0 { return false }
            }
            f = (f == 2) ? 3 : (f + 2)
        }
        if let a = first, m > 1, m != a, isPrime64(m) { return true }
        return false
    }

    static func isPrimePower(_ n: UInt64) -> Bool {
        if n < 4 { return false }
        if n % 2 == 0 {
            var x = n; while x % 2 == 0 { x /= 2 }; return x == 1
        }
        var p: UInt64 = 3
        while p * p <= n {
            if n % p == 0 {
                var x = n; while x % p == 0 { x /= p }; return x == 1
            }
            p += 2
        }
        return false
    }

    // Deterministic Miller–Rabin for 64-bit
    static func isPrime64(_ n: UInt64) -> Bool {
        if n < 2 { return false }

        // quick small-prime handling
        let small: [UInt64] = [2,3,5,7,11,13,17,19,23,29,31,37]
        if small.contains(n) { return true }
        for p in small { if n % p == 0 { return false } }

        // write n-1 = d * 2^s
        var d = n - 1
        var s: UInt64 = 0
        while (d & 1) == 0 { d >>= 1; s &+= 1 }

        func mulmod(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
            let prod = a.multipliedFullWidth(by: b)
            let (_, r) = m.dividingFullWidth((prod.high, prod.low))
            return r
        }

        func modPow(_ a: UInt64, _ e: UInt64, _ m: UInt64) -> UInt64 {
            var base = a % m, exp = e, res: UInt64 = 1
            while exp > 0 {
                if (exp & 1) == 1 { res = mulmod(res, base, m) }
                base = mulmod(base, base, m)
                exp >>= 1
            }
            return res
        }

        // deterministic bases for 64-bit
        let bases: [UInt64] = [2,3,5,7,11,13]
        for a in bases {
            if a % n == 0 { continue }
            var x = modPow(a, d, n)
            if x == 1 || x == n - 1 { continue }
            var r: UInt64 = 1
            var composite = true
            while r < s {
                x = mulmod(x, x, n)
                if x == n - 1 { composite = false; break }
                r &+= 1
            }
            if composite { return false }
        }
        return true
    }

    static func factorizationString(of n: UInt64) -> String {
        if n < 2 { return "\(n)" }
        var m = n
        var parts: [String] = []
        var p: UInt64 = 2
        while p * p <= m {
            while m % p == 0 { parts.append(String(p)); m /= p }
            p = (p == 2) ? 3 : (p + 2)
        }
        if m > 1 { parts.append(String(m)) }
        return "\(n) = " + parts.joined(separator: " × ")
    }
}
