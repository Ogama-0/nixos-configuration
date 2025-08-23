{ config, lib, ... }:

{
  programs.xcompose = {
    enable = true;
    includeLocaleCompose = true;
    loadConfigInEnv = false;

    sequences.Multi_key = {
      # Accents français
      e.grave = "è";
      E.grave = "È";
      e.apostrophe = "é";
      E.apostrophe = "É";
      a.grave = "à";
      A.grave = "À";
      u.grave = "ù";
      U.grave = "Ù";
      e.quotedbl = "ë";
      E.quotedbl = "Ë";
      a.quotedbl = "ä";
      A.quotedbl = "Ä";

      quotedbl.quotedbl = "¨";
      apostrophe.apostrophe = "´";

      s.s = "ß";

      # Lettres grecques minuscules
      g = {
        a = "α";
        b = "β";
        g = "γ";
        d = "δ";
        e = "ε";
        z = "ζ";
        h = "η";
        u = "θ";
        i = "ι";
        k = "κ";
        l = "λ";
        m = "μ";
        n = "ν";
        x = "ξ";
        q.o = "ο";
        p = "π";
        r = "ρ";
        s = "σ";
        t = "τ";
        y = "υ";
        f = "φ";
        o = "ω";
      };

      # Lettres grecques majuscules
      G = {
        A = "Α";
        B = "Β";
        G = "Γ";
        D = "Δ";
        E = "Ε";
        Z = "Ζ";
        H = "Η";
        U = "Θ";
        I = "Ι";
        K = "Κ";
        L = "Λ";
        M = "Μ";
        N = "Ν";
        X = "Ξ";
        Q.O = "Ο";
        P = "Π";
        R = "Ρ";
        S = "Σ";
        T = "Τ";
        Y = "Υ";
        F = "Φ";
        O = "Ω";
      };

      # Symboles mathématiques
      l.equal = "≤";
      g.equal = "≥";
      s.u.m = "∑";
      asciitilde.asciitilde = "≈";

      # Lettres doubles (𝔸, ℂ, ℝ, etc.)
      M = {
        A = "𝔸";
        B = "𝔹";
        C = "ℂ";
        D = "𝔻";
        E = "𝔼";
        F = "𝔽";
        G = "𝔾";
        H = "ℍ";
        I = "𝕀";
        J = "𝕁";
        K = "𝕂";
        L = "𝕃";
        M = "𝕄";
        N = "ℕ";
        O = "𝕆";
        P = "ℙ";
        Q = "ℚ";
        R = "ℝ";
        S = "𝕊";
        T = "𝕋";
        U = "𝕌";
        V = "𝕍";
        X = "𝕏";
        Y = "𝕐";
        Z = "ℤ";
      };

      # Autres symboles
      o.o = "∞";
      minus.greater = "→";
      less.minus = "←";
      less.greater.minus = "↔";
      equal.greater = "⇒";
      less.equal = "⇐";
      less.greater.equal = "⇔";
      "0"."0" = "°";
      minus.minus = "—";
    };
  };
}
