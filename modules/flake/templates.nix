# `nix flake init` templates. Self-contained flakes for project scaffolding,
# unrelated to the host configurations.
{ ... }:
{
  flake.templates = import ../../templates;
}
