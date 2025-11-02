//
//  BaseVerifier.swift
//  BaseVerifier
//
//  Created by Byul Kang
//

import Foundation
import Combine

class BaseVerifier: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var violations: [Violation] = []
    @Published var logMessages: [String] = []
    @Published var primesChecked: Int = 0
    @Published var isCompleted: Bool = false
    @Published var testedLimit: Int = 0
    
    private var task: Task<Void, Never>?
    private var shouldStop = false
    
    let threadCount = ProcessInfo.processInfo.activeProcessorCount
    
    // MARK: - Start Verification
    func start(base: Int, limit: Int) {
        reset()
        testedLimit = limit
        shouldStop = false
        
        addLog("🚀 Starting verification for Base-\(base)")
        addLog("   Range: 2 to \(limit.formatted())")
        addLog("   Property: S\(base)(p) ∈ {1, prime, semiprime, prime power}")
        addLog("")
        
        task = Task {
            await runVerification(base: base, limit: limit)
        }
    }
    
    // MARK: - Stop Verification
    func stop() {
        shouldStop = true
        task?.cancel()
        addLog("❌ Verification stopped by user")
    }
    
    // MARK: - Reset
    private func reset() {
        progress = 0.0
        violations = []
        logMessages = []
        primesChecked = 0
        isCompleted = false
    }
    
    // MARK: - Main Verification
    private func runVerification(base: Int, limit: Int) async {
        let startTime = Date()
        var localPrimesChecked = 0
        
        // Simple sequential check (for GUI, not optimized for speed)
        for p in 2...limit {
            if shouldStop {
                await MainActor.run {
                    addLog("Verification cancelled")
                }
                return
            }
            
            if isPrime(p) {
                localPrimesChecked += 1
                let digitSum = sumOfDigits(p, base: base)
                
                // Check if violates the refined conjecture
                if !isValid(digitSum) {
                    let factors = factorize(digitSum)
                    let factorString = factors.map(String.init).joined(separator: " × ")
                    
                    await MainActor.run {
                        violations.append(Violation(
                            prime: p,
                            digitSum: digitSum,
                            factorization: "\(digitSum) = \(factorString)"
                        ))
                        addLog("❗️ VIOLATION: p=\(p), S\(base)(p)=\(digitSum)")
                    }
                }
                
                // Update progress
                if localPrimesChecked % 10000 == 0 {
                    await MainActor.run {
                        progress = Double(p) / Double(limit)
                        primesChecked = localPrimesChecked
                        
                        if primesChecked % 100000 == 0 {
                            addLog("   Checked \(primesChecked.formatted()) primes...")
                        }
                    }
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        await MainActor.run {
            progress = 1.0
            isCompleted = true
            addLog("")
            addLog("🏁 Verification complete!")
            addLog("   Duration: \(String(format: "%.2f", duration)) seconds")
            addLog("   Primes checked: \(localPrimesChecked.formatted())")
            
            if violations.isEmpty {
                addLog("   ✅ Result: NO VIOLATIONS")
                addLog("   Base-\(base) satisfies the conjecture up to \(limit.formatted())")
            } else {
                addLog("   ❌ Result: \(violations.count) VIOLATION(S) FOUND")
            }
        }
    }
    
    // MARK: - Validation
    private func isValid(_ n: Int) -> Bool {
        // Check if n satisfies: 1, prime, semiprime, or prime power
        if n == 1 { return true }
        if isPrime(n) { return true }
        if isSemiprime(n) { return true }
        if isPrimePower(n) { return true }
        return false
    }
    
    // MARK: - Primality Test
    private func isPrime(_ n: Int) -> Bool {
        if n <= 1 { return false }
        if n <= 3 { return true }
        if n % 2 == 0 || n % 3 == 0 { return false }
        var i = 5
        while i * i <= n {
            if n % i == 0 || n % (i + 2) == 0 { return false }
            i += 6
        }
        return true
    }
    
    // MARK: - Digit Sum
    private func sumOfDigits(_ n: Int, base: Int) -> Int {
        var num = n
        var sum = 0
        while num > 0 {
            sum += num % base
            num /= base
        }
        return sum
    }
    
    // MARK: - Semiprime Check
    private func isSemiprime(_ n: Int) -> Bool {
        if n < 4 { return false }
        
        var num = n
        var primeFactorCount = 0
        
        while num % 2 == 0 {
            primeFactorCount += 1
            if primeFactorCount > 2 { return false }
            num /= 2
        }
        
        var i = 3
        while i * i <= num {
            while num % i == 0 {
                primeFactorCount += 1
                if primeFactorCount > 2 { return false }
                num /= i
            }
            i += 2
        }
        
        if num > 1 {
            primeFactorCount += 1
        }
        
        return primeFactorCount == 2
    }
    
    // MARK: - Prime Power Check
    private func isPrimePower(_ n: Int) -> Bool {
        if n < 2 { return false }
        if isPrime(n) { return true }
        
        var num = n
        var firstPrimeFactor: Int? = nil
        
        if num % 2 == 0 {
            firstPrimeFactor = 2
            while num % 2 == 0 {
                num /= 2
            }
            if num > 1 { return false }
            return true
        }
        
        var i = 3
        while i * i <= num {
            if num % i == 0 {
                if firstPrimeFactor == nil {
                    firstPrimeFactor = i
                } else if firstPrimeFactor != i {
                    return false
                }
                
                while num % i == 0 {
                    num /= i
                }
            }
            i += 2
        }
        
        if num > 1 {
            if firstPrimeFactor == nil {
                return true
            } else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Factorization
    private func factorize(_ n: Int) -> [Int] {
        var factors: [Int] = []
        var num = n
        var d = 2
        
        while d * d <= num {
            while num % d == 0 {
                factors.append(d)
                num /= d
            }
            d += (d == 2 ? 1 : 2)
        }
        
        if num > 1 {
            factors.append(num)
        }
        
        return factors
    }
    
    // MARK: - Logging
    private func addLog(_ message: String) {
        logMessages.append(message)
    }
}
