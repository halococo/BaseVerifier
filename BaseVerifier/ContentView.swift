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
    @State private var checkPrimeText: String = "31"

    enum ConcurrencyChoice: String, CaseIterable, Identifiable {
        case auto = "auto", x1 = "x1", x2 = "x2", x4 = "x4"
        var id: String { rawValue }
        var threads: Int { self == .auto ? 0 : Int(String(rawValue.dropFirst())) ?? 1 }
    }
    @State private var concurrency: ConcurrencyChoice = .auto

    private func isPrimeSmall(_ n: Int) -> Bool {
        if n < 2 { return false }
        if n % 2 == 0 { return n == 2 }
        var i = 3
        while i * i <= n { if n % i == 0 { return false }; i += 2 }
        return true
    }

    private var startDisabledReason: String? {
        guard let b = UInt64(baseText) else { return "base must be an integer ≥ 2" }
        if b < 2 { return "base must be ≥ 2" }
        if !Math.isPrime64(b) { return "base must be a PRIME" }
        guard let limit = UInt64(limitText), limit >= 10 else { return "limit must be an integer ≥ 10" }
        if vm.isRunning { return "already running" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            GroupBox {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    HStack {
                        Text("Base").frame(width: 90, alignment: .leading)
                        TextField("prime base (e.g. 7, 13…)", text: $baseText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .disabled(vm.isRunning)
                            .onReceive(Just(baseText)) { _ in baseText = baseText.filter(\.isNumber) }
                    }
                    HStack {
                        Text("Limit").frame(width: 90, alignment: .leading)
                        TextField("upper bound", text: $limitText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .disabled(vm.isRunning)
                            .onReceive(Just(limitText)) { _ in limitText = limitText.filter(\.isNumber) }
                        ForEach([("1M","1000000"),("10M","10000000"),("100M","100000000"),("1B","1000000000")], id: \.0) { t in
                            Button(t.0) { limitText = t.1 }.buttonStyle(.bordered).disabled(vm.isRunning)
                        }
                    }
                    HStack {
                        Text("Concurrency").frame(width: 100, alignment: .leading)
                        Picker("", selection: $concurrency) {
                            ForEach(ConcurrencyChoice.allCases) { c in Text(c.rawValue).tag(c) }
                        }
                        .frame(width: 120)
                        .disabled(vm.isRunning)
                        .help("""
                        How many worker threads to use.
                        • auto: use system cores (recommended)
                        • x1: single thread (safest)
                        • x2 / x4: more threads; may run hotter
                        """)
                    }
                    Button {
                        if vm.isRunning { vm.stop() } else { startVerification() }
                    } label: {
                        Label(vm.isRunning ? "Stop" : "Start",
                              systemImage: vm.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isRunning ? .red : .green)
                    .disabled(startDisabledReason != nil)
                }

                HStack {
                    ProgressView(value: vm.progress).frame(maxWidth: .infinity)
                    Text("Primes: \(vm.primesChecked.formatted())")
                        .font(.caption).foregroundColor(.secondary)
                }.padding(.top, 4)
            }

            GroupBox("Results") {
                if let reason = startDisabledReason, !vm.isRunning {
                    Text("Cannot start: \(reason)").font(.caption).foregroundColor(.orange)
                }
                if !vm.statusLine.isEmpty {
                    Text(vm.statusLine)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(vm.violationFound ? .red : .green)
                        .padding(.bottom, 4)
                }
                ForEach(vm.logLines.suffix(8), id: \.self) { line in
                    Text(line).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                }
            }

            GroupBox {
                HStack {
                    Text("Check prime")
                    TextField("n", text: $checkPrimeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onReceive(Just(checkPrimeText)) { _ in checkPrimeText = checkPrimeText.filter(\.isNumber) }
                    Button("Check") {
                        if let n = Int(checkPrimeText) {
                            let p = isPrimeSmall(n)
                            vm.appendLog("Check \(n): \(p ? "prime" : "composite")")
                        }
                    }.buttonStyle(.bordered)
                    if let n = Int(checkPrimeText) {
                        Text(isPrimeSmall(n) ? "Prime" : "Composite").font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 520)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Prime Base Verifier").font(.system(size: 28, weight: .bold))
            Text("Digit-sum conjecture including prime powers")
                .font(.footnote).foregroundColor(.secondary)
            Link("Source code (GitHub)", destination: URL(string: "https://github.com/halococo/BaseVerifier")!)
                .font(.caption)
        }.frame(maxWidth: .infinity)
    }

    private func startVerification() {
        guard let b = UInt64(baseText), let limit = UInt64(limitText) else { return }
        vm.start(base: b, limit: limit, threads: concurrency.threads)
    }
}
