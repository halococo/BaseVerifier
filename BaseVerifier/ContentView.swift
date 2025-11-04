//
//  ContentView.swift
//  BaseVerifier
//
//  Created by Byul Kang 
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var vm = BaseVerifier()

    @State private var baseText: String = "31"
    @State private var limitText: String = "1000000"
    @State private var running = false

    // Prime checker
    @State private var checkPrimeText: String = "31"
    @State private var checkResult: String = ""

    var body: some View {
        VStack(spacing: 22) {
            // Header
            VStack(spacing: 6) {
                Text("Prime Base Verifier")
                    .font(.system(size: 28, weight: .bold))
                Text("Digit-sum conjecture including prime powers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Link("Source code (GitHub)", destination: URL(string: "https://github.com/halococo/BaseVerifier")!)
                    .font(.caption)
            }
            .padding(.top, 8)

            // Controls
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Base")
                            .frame(width: 80, alignment: .leading)
                        TextField("Enter base (prime ≥ 2)", text: $baseText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(running)
                            .frame(width: 220)
                        Spacer()
                    }

                    HStack {
                        Text("Limit")
                            .frame(width: 80, alignment: .leading)
                        TextField("Upper bound (e.g. 1000000000)", text: $limitText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(running)
                            .frame(width: 220)

                        HStack(spacing: 8) {
                            Button("1M") { limitText = "1000000" }.disabled(running)
                            Button("10M") { limitText = "10000000" }.disabled(running)
                            Button("100M") { limitText = "100000000" }.disabled(running)
                            Button("1B") { limitText = "1000000000" }.disabled(running)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Only domain warning (no candidate whitelist)
                    HStack {
                        if let base = UInt64(baseText), !BaseVerifier.isPrime64(base) {
                            Label("Base must be prime for this conjecture.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: toggle) {
                            Label(running ? "Stop" : "Start", systemImage: running ? "stop.fill" : "play.fill")
                                .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(running ? .red : .green)
                        .disabled(!canRun)

                        ProgressView(value: vm.progress)
                            .frame(maxWidth: .infinity)
                        Text("Primes: \(vm.primesChecked.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Results
            GroupBox("Results") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if vm.violations.isEmpty && vm.done {
                            Label("No violations found up to \(formattedLimit()).", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if vm.violations.isEmpty {
                            Label("Running…", systemImage: "hourglass")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("\(vm.violations.count) violation(s) found.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        Spacer()
                    }

                    if !vm.statusLine.isEmpty {
                        Text(vm.statusLine)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(vm.violations) { v in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("p = \(v.prime)")
                            Text("digit sum = \(v.digitSum)")
                            Text(v.factorization)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.07))
                        .cornerRadius(8)
                    }
                }
            }

            // Prime check tool
            GroupBox("Check prime") {
                HStack {
                    TextField("Enter n", text: $checkPrimeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Button("Check") {
                        if let x = UInt64(checkPrimeText) {
                            checkResult = BaseVerifier.isPrime64(x) ? "Prime" : "Composite"
                        } else {
                            checkResult = "Invalid"
                        }
                    }
                    .buttonStyle(.bordered)
                    Text(checkResult)
                        .foregroundStyle(checkResult == "Prime" ? .green : .primary)
                    Spacer()
                }
            }

            Spacer(minLength: 6)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 640)
    }

    private var canRun: Bool {
        guard let base = UInt64(baseText), let limit = UInt64(limitText) else { return false }
        if limit < 2 { return false }
        // Only domain restriction: base must be prime (composite bases are outside the conjecture)
        if !BaseVerifier.isPrime64(base) { return false }
        return !running
    }

    private func toggle() {
        if running {
            vm.stop()
            running = false
        } else {
            guard let base = UInt64(baseText), let limit = UInt64(limitText) else { return }
            running = true
            vm.start(base: base, limit: limit)
        }
    }

    private func formattedLimit() -> String {
        guard let n = UInt64(limitText) else { return limitText }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
