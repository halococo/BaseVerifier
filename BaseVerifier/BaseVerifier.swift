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

@MainActor
final class BaseVerifier: ObservableObject {

    // MARK: - Published UI state
    @Published var progress: Double = 0.0
    @Published var primesChecked: UInt64 = 0
    @Published var statusLine: String = ""
    @Published var isRunning: Bool = false
    @Published var violationFound: Bool = false
    @Published var logLines: [String] = []

    // control
    private var task: Task<Void, Never>? = nil
    private let stopBox = StopBox()

    // UI update cadence
    private let stepBatch: UInt64 = 8_192

    // open for ContentView "Check" button
    func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }

    func start(base: UInt64, limit: UInt64, threads: Int) {
        stop() // clean up previous
        progress = 0
        primesChecked = 0
        statusLine = "Running..."
        violationFound = false
        isRunning = true
        stopBox.set(false)
        appendLog("🚀 Start: base=\(base), limit=\(limit.formatted()), threads=\(threads > 0 ? threads : -1)")

        task = Task { await run(base: base, limit: limit, threads: threads) }
    }

    func stop() {
        stopBox.set(true)
        task?.cancel()
        task = nil
    }

    private func run(base: UInt64, limit: UInt64, threads: Int) async {
        let started = Date()
        let t = threads > 0 ? threads : max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunk = max<UInt64>(1, limit / UInt64(t))

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
                let start = UInt64(i) * chunk + (i == 0 ? 2 : 1)
                let end   = (i == t - 1) ? limit : (UInt64(i + 1) * chunk - 1)

                group.addTask { [stepBatch, stopBox] in
                    var processed: UInt64 = 0
                    var localPrimes: UInt64 = 0
                    var n = start

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

                        processed &+= 1
                        n &+= 1

                        if (processed % stepBatch) == 0 || n > end {
                            lock.lock()
                            globalProcessed &+= processed
                            globalPrimes    &+= localPrimes
                            let raw = min(1.0, Double(globalProcessed) / Double(max(1, limit - 1)))
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
        isRunning = false
        progress = 1.0

        if stopBox.get() {
            statusLine = "Stopped."
            appendLog("Stopped.")
            return
        }

        if let v = first {
            violationFound = true
            statusLine = "❌ Violation: p=\(v.p)  S(p)=\(v.s)  (\(v.fac))"
            appendLog(statusLine)
        } else {
            violationFound = false
            statusLine = "✅ No violations found up to \(limit.formatted())."
            appendLog("Done in \(String(format: "%.2f", elapsed)) s – primes: \(primesChecked.formatted())")
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
        if n < 6 { return false } // 2*3
        var m = n
        var first: UInt64? = nil
        var f: UInt64 = 2
        while f*f <= m {
            if m % f == 0 {
                if first == nil { first = f } else { if first! == f { return false } else { m /= f; return m == 1 } }
                m /= f
                while m % f == 0 { return false } // same factor repeats => prime power-like
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
        while p*p <= n {
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
        let bases: [UInt64] = [2, 3, 5, 7, 11, 13]
        for a in bases {
            if a % n == 0 { continue }            // (harmless short-circuit)
            var x = modPow(a, d, n)               // a,d,n are all UInt64
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
