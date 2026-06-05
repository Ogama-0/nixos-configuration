{ pkgs, ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "zen.desktop";
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
      "x-scheme-handler/about" = "zen-beta.desktop";
      "x-scheme-handler/unknown" = "zen-beta.desktop";
      "x-scheme-handler/discord" = "vesktop.desktop";
      "application/pdf" = "zen-beta.desktop";
      "application/x-extension-htm" = "zen-beta.desktop";
      "application/x-extension-html" = "zen-beta.desktop";
      "application/x-extension-shtml" = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
      "application/x-extension-xhtml" = "zen-beta.desktop";
      "application/x-extension-xht" = "zen-beta.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };

  };
}
