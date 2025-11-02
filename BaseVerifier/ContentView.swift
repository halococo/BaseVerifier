//
//  ContentView.swift
//  BaseVerifier
//
//  Created by Byul Kang
//

import SwiftUI

struct ContentView: View {
    @StateObject private var verifier = BaseVerifier()
    
    @State private var selectedBase: Int = 19
    @State private var testLimit: String = "1000000000"
    @State private var isRunning = false
    
    let availableBases = [7, 13, 19, 31, 37, 43, 61, 211, 421]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Prime Base Verifier")
                    .font(.system(size: 28, weight: .bold))
                
                Text("Refined Conjecture with Prime Powers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Link("Paper: doi.org/10.5281/zenodo.17502674",
                     destination: URL(string: "https://doi.org/10.5281/zenodo.17502674")!)
                    .font(.caption)
            }
            .padding()
            
            Divider()
            
            // Settings
            VStack(alignment: .leading, spacing: 15) {
                Text("Settings")
                    .font(.headline)
                
                // Base Selection
                HStack {
                    Text("Base:")
                        .frame(width: 100, alignment: .leading)
                    
                    Picker("", selection: $selectedBase) {
                        ForEach(availableBases, id: \.self) { base in
                            Text("Base-\(base)").tag(base)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .disabled(isRunning)
                    
                    if selectedBase == 19 {
                        Text("⭐ Revival Candidate!")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Test Limit
                HStack {
                    Text("Test Limit:")
                        .frame(width: 100, alignment: .leading)
                    
                    TextField("Limit", text: $testLimit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .disabled(isRunning)
                    
                    Text(formatNumber(testLimit))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Quick Presets
                HStack {
                    Text("Quick:")
                        .frame(width: 100, alignment: .leading)
                    
                    Button("1M") { testLimit = "1000000" }
                        .disabled(isRunning)
                    Button("10M") { testLimit = "10000000" }
                        .disabled(isRunning)
                    Button("100M") { testLimit = "100000000" }
                        .disabled(isRunning)
                    Button("1B") { testLimit = "1000000000" }
                        .disabled(isRunning)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Progress
            if isRunning {
                VStack(spacing: 10) {
                    ProgressView(value: verifier.progress) {
                        HStack {
                            Text("Testing Base-\(selectedBase)...")
                            Spacer()
                            Text("\(Int(verifier.progress * 100))%")
                        }
                    }
                    
                    Text("Primes tested: \(verifier.primesChecked.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Control Button
            Button(action: toggleVerification) {
                Label(
                    isRunning ? "Stop" : "Start Verification",
                    systemImage: isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .red : .green)
            .disabled(testLimit.isEmpty)
            
            Divider()
            
            // Results
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Results")
                        .font(.headline)
                    
                    if verifier.violations.isEmpty && verifier.isCompleted {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("✅ No violations found!")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        Text("Base-\(selectedBase) satisfies the refined conjecture up to \(verifier.testedLimit.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else if !verifier.violations.isEmpty {
                        ForEach(verifier.violations, id: \.prime) { violation in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("VIOLATION FOUND!")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.red)
                                        .bold()
                                }
                                
                                Text("Prime (p): \(violation.prime.formatted())")
                                    .font(.system(.caption, design: .monospaced))
                                
                                Text("S\(selectedBase)(p) = \(violation.digitSum)")
                                    .font(.system(.caption, design: .monospaced))
                                
                                Text("Factorization: \(violation.factorization)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    } else {
                        Text("Click 'Start Verification' to begin testing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Log messages
                    ForEach(verifier.logMessages.suffix(10), id: \.self) { message in
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 250)
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
        .frame(minWidth: 700, minHeight: 700)
    }
    
    func toggleVerification() {
        if isRunning {
            verifier.stop()
            isRunning = false
        } else {
            guard let limit = Int(testLimit) else { return }
            isRunning = true
            verifier.start(base: selectedBase, limit: limit)
        }
    }
    
    func formatNumber(_ str: String) -> String {
        guard let num = Int(str) else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? ""
    }
}

// MARK: - Violation Model
struct Violation: Identifiable {
    let id = UUID()
    let prime: Int
    let digitSum: Int
    let factorization: String
}

#Preview {
    ContentView()
}
