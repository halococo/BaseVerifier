# Prime Base Verifier

A macOS GUI tool for verifying the **digit-sum conjecture on prime bases**,  
as proposed in *Byul Kang (2025)*.

This app tests whether, for a given **prime base** \(b\),  
every prime \(p\) satisfies the following property:

> **GitHub-safe expression:**  
> S_b(p) ∈ {1} ∪ {Primes} ∪ {Semiprimes} ∪ {Prime Powers}

---

## 🧩 Features
- SwiftUI GUI for interactive exploration  
- Multi-threaded verification up to billions of primes  
- Real-time progress tracking  
- Built-in prime checker tool  
- Deterministic 64-bit Miller–Rabin test  
- No artificial base filtering — open computation across all prime bases

---

## 🖥 Requirements
- macOS **14.0+ (Sonoma)**
- Xcode **15.0+**
- Swift **5.9+**

---

## ⚙️ How to Build and Run

1. Open **Xcode**
2. Create a new **macOS App** project  
   - Name: `BaseVerifier` (or any name)  
   - Interface: **SwiftUI**  
   - Language: **Swift**
3. Delete the default `ContentView.swift` and `YourAppApp.swift`
4. Add these files from the repository:
   - `BaseVerifierApp.swift`  
   - `BaseVerifier.swift`  
   - `ContentView.swift`  
5. Press **⌘R** to build and run

---

## 🧪 Usage

1. Enter a **prime base** (e.g., 7, 13, 19, 31)  
2. Set a **test limit** (e.g., 1,000,000,000)  
3. Click **Start**  
4. The app will scan all primes up to that limit and report any violations  
5. You can also use the **Check Prime** field to test primality instantly

---

## 📄 Related Paper

**Byul Kang (2025)**  
*A Conjecture on Prime Bases with a Specific Digit Sum Property*  
Zenodo. DOI: [10.5281/zenodo.17518629](https://doi.org/10.5281/zenodo.17518629)

---

## 🧠 Citation

If you use this software or data derived from it, please cite:

> Kang, B. (2025). *A Conjecture on Prime Bases with a Specific Digit Sum Property.*  
> Zenodo. DOI: [10.5281/zenodo.17518629](https://doi.org/10.5281/zenodo.17518629)

---

## 📘 License
Released under the **MIT License** — freely usable for academic and personal research.

---

<p align="center">
  <a href="https://doi.org/10.5281/zenodo.17518629">
    <img src="https://zenodo.org/badge/DOI/10.5281/zenodo.17518629.svg" alt="DOI Badge">
  </a>
</p>
