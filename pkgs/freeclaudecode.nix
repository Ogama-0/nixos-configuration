{
  lib,
  python314,
  fetchFromGitHub,
  pkgs,
}:
let
  python = python314.override {
    packageOverrides = self: super: {
      astor = super.astor.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };

  src = fetchFromGitHub {
    owner = "Alishahryar1";
    repo = "free-claude-code";
    rev = "main";
    # hash = "sha256-rr3VfdCvyFAXuZNKTJ95nzx1S1aGvpn/t1i5VPrdlo8=";
    hash = "sha256-3t5POOE+tJmKsCdTHuUqSfkHX36BGxBC0M0OkN2QWPk=";
  };
in
python.pkgs.buildPythonPackage {
  pname = "free-claude-code";
  version = "2.0.0";
  pyproject = true;
  inherit src;

  build-system = [ python.pkgs.hatchling ];

  dependencies = with python.pkgs; [
    pkgs.claude-code
    fastapi
    uvicorn
    httpx
    markdown-it-py
    pydantic
    python-dotenv
    tiktoken
    python-telegram-bot
    discordpy
    pydantic-settings
    openai
    loguru
    jsonschema
  ];

  pythonRelaxDeps = [
    "discord-py"
    "fastapi"
    "markdown-it-py"
    "openai"
    "pydantic"
    "pydantic-settings"
    "tiktoken"
    "uvicorn"
  ];

  doCheck = false;

  meta = {
    description = "Route Claude Code Anthropic API traffic to any LLM provider";
    homepage = "https://github.com/Alishahryar1/free-claude-code";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.unix;
    mainProgram = "fcc-server";
  };
}
