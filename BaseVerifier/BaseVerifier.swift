//
//  BaseVerifier.swift
//  BaseVerifier
//
//  Created by Byul Kang
//  Core engine: 64-bit deterministic Miller–Rabin, safe 128-bit mul via fullWidth
//

import Foundation
import Combine

struct Violation: Identifiable, Sendable {
    let id = UUID()
    let prime: UInt64
    let digitSum: UInt64
    let factorization: String
}

final class BaseVerifier: ObservableObject {

    // MARK: - Published UI state
    @Published var progress: Double = 0.0
    @Published var primesChecked: UInt64 = 0
    @Published var statusLine: String = "Idle"
    @Published var done: Bool = false
    @Published var violations: [Violation] = []

    // MARK: - Internal state
    private var task: Task<Void, Never>?
    private let stateLock = NSLock()
    private var _shouldStop = false
    private var _limit: UInt64 = 0
    private var _base: UInt64 = 7

    // MARK: - Control
    func stop() {
        stateLock.lock(); _shouldStop = true; stateLock.unlock()
        task?.cancel()
    }

    func start(base: UInt64, limit: UInt64) {
        // reset
        stop()
        progress = 0
        primesChecked = 0
        violations = []
        done = false
        statusLine = "Preparing…"

        stateLock.lock()
        _shouldStop = false
        _limit = limit
        _base  = base
        stateLock.unlock()

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.run()
        }
    }

    // MARK: - Main loop
    private func run() async {
        let base = _base
        let limit = _limit

        // Domain restriction: the conjecture targets prime bases.
        if !Self.isPrime64(base) {
            await MainActor.run {
                self.statusLine = "Base \(base) is not prime — the conjecture is defined for prime bases."
                self.done = true
            }
            return
        }

        let t0 = Date()
        var localPrimes: UInt64 = 0
        var lastN: UInt64 = 0
        let tick: UInt64 = 50_000 // UI refresh cadence

        @inline(__always) func shouldStop() -> Bool {
            stateLock.lock(); let s = _shouldStop; stateLock.unlock()
            return s || Task.isCancelled
        }

        await MainActor.run {
            self.statusLine = "Running (base \(base))…"
        }

        var n: UInt64 = 2
        while n <= limit {
            if shouldStop() { break }

            if Self.isPrime64(n) {
                localPrimes &+= 1
                let s = Self.digitSum(n, base: base)
                if !Self.isValidDigitSum(s) {
                    let fac = Self.factorizationString(of: s)
                    let v = Violation(prime: n, digitSum: s, factorization: "\(s) = \(fac)")
                    await MainActor.run {
                        self.violations.append(v)
                        self.statusLine = "Violation at p=\(n)"
                    }
                    // continue scanning; do not alter results
                }
            }

            if n - lastN >= tick {
                lastN = n
                let p = Double(n) / Double(limit)
                let checked = localPrimes
                await MainActor.run {
                    self.progress = min(max(p, 0), 1)
                    self.primesChecked = checked
                }
                try? await Task.sleep(nanoseconds: 0) // cooperative yield
            }

            n &+= 1
        }

        let sec = Date().timeIntervalSince(t0)
        await MainActor.run {
            self.done = true
            if self.violations.isEmpty {
                self.statusLine = "Done. No violations. Primes checked: \(localPrimes.formatted()) (\(String(format: "%.2f", sec)) s)"
            } else {
                self.statusLine = "Done. \(self.violations.count) violation(s). Primes checked: \(localPrimes.formatted()) (\(String(format: "%.2f", sec)) s)"
            }
            self.progress = 1.0
            self.primesChecked = localPrimes
        }
    }

    // MARK: - Math helpers (static → no actor isolation)
    // Deterministic Miller–Rabin for 64-bit
    static func isPrime64(_ n: UInt64) -> Bool {
        if n < 2 { return false }
        for p in [2,3,5,7,11,13,17,19,23,29,31] as [UInt64] {
            if n == p { return true }
            if n % p == 0 { return n == p }
        }
        var d = n - 1
        var s: UInt64 = 0
        while d % 2 == 0 { d /= 2; s &+= 1 }
        // sufficient base set for 64-bit
        let bases: [UInt64] = [2, 3, 5, 7, 11, 13]
        for a in bases {
            if a % n == 0 { continue }
            var x = powmod(a, d, n)
            if x == 1 || x == n - 1 { continue }
            var r: UInt64 = 1
            var witness = true
            while r < s {
                x = mulmod(x, x, n)
                if x == n - 1 { witness = false; break }
                r &+= 1
            }
            if witness { return false }
        }
        return true
    }

    static func mulmod(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
        let (hi, lo) = a.multipliedFullWidth(by: b)
        let (_, r)   = m.dividingFullWidth((hi, lo))
        return r
    }

    static func powmod(_ base: UInt64, _ exp: UInt64, _ mod: UInt64) -> UInt64 {
        if mod == 1 { return 0 }
        var b = base % mod
        var e = exp
        var res: UInt64 = 1
        while e > 0 {
            if (e & 1) == 1 { res = mulmod(res, b, mod) }
            b = mulmod(b, b, mod)
            e >>= 1
        }
        return res
    }

    static func digitSum(_ n: UInt64, base: UInt64) -> UInt64 {
        var x = n
        var s: UInt64 = 0
        while x > 0 {
            s &+= x % base
            x /= base
        }
        return s
    }

    // prime power? (primes count as prime powers)
    static func isPrimePower(_ n: UInt64) -> Bool {
        if n < 2 { return false }
        if isPrime64(n) { return true }
        var x = n
        var p: UInt64 = 2
        while p*p <= x && x % p != 0 { p &+= (p == 2 ? 1 : 2) }
        if p*p > x { return false }
        while x % p == 0 { x /= p }
        return x == 1
    }

    // semiprime? (exactly two prime factors with multiplicity)
    static func isSemiprime(_ n: UInt64) -> Bool {
        if n < 4 { return false }
        var x = n
        var cnt = 0
        while x % 2 == 0 { cnt += 1; if cnt > 2 { return false }; x /= 2 }
        var f: UInt64 = 3
        while f*f <= x {
            while x % f == 0 {
                cnt += 1
                if cnt > 2 { return false }
                x /= f
            }
            f &+= 2
        }
        if x > 1 { cnt += 1 }
        return cnt == 2
    }

    // 1, prime, semiprime, or prime power
    static func isValidDigitSum(_ s: UInt64) -> Bool {
        if s == 1 { return true }
        if isPrime64(s) { return true }
        if isSemiprime(s) { return true }
        if isPrimePower(s) { return true }
        return false
    }

    static func factorizationString(of n: UInt64) -> String {
        if n < 2 { return "\(n)" }
        var x = n
        var parts: [String] = []
        var p: UInt64 = 2
        var c = 0
        while x % p == 0 { c += 1; x /= p }
        if c > 0 { parts.append(c == 1 ? "2" : "2^\(c)") }
        p = 3
        while p*p <= x {
            c = 0
            while x % p == 0 { c += 1; x /= p }
            if c > 0 { parts.append(c == 1 ? "\(p)" : "\(p)^\(c)") }
            p &+= 2
        }
        if x > 1 { parts.append("\(x)") }
        return parts.joined(separator: " · ")
    }
}
