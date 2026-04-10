# Home Manager module for goose.
#
# Usage (flake):
#
#   {
#     inputs.goose.url = "github:block/goose";
#
#     outputs = { self, nixpkgs, home-manager, goose, ... }: {
#       homeConfigurations."you" = home-manager.lib.homeManagerConfiguration {
#         pkgs = import nixpkgs { system = "x86_64-linux"; };
#         modules = [
#           goose.homeManagerModules.default
#           {
#             programs.goose = {
#               enable = true;
#               settings = {
#                 GOOSE_PROVIDER = "anthropic";
#                 GOOSE_MODEL = "claude-sonnet-4-20250514";
#                 GOOSE_MODE = "smart_approve";
#                 extensions.developer = {
#                   enabled = true;
#                   type = "builtin";
#                   name = "developer";
#                 };
#               };
#             };
#           }
#         ];
#       };
#     };
#   }
{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.goose;

  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };

  configFile = yamlFormat.generate "goose-config.yaml" cfg.settings;

  providerFiles =
    lib.mapAttrs' (name: value:
      lib.nameValuePair "goose/custom_providers/${name}.json" {
        source = jsonFormat.generate "goose-provider-${name}.json" value;
      }) cfg.customProviders;
in
{
  meta.maintainers = [ ];

  options.programs.goose = {
    enable = lib.mkEnableOption "goose, an open source extensible AI agent";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        self.packages.${pkgs.stdenv.hostPlatform.system}.default or null;
      defaultText = lib.literalExpression
        "goose.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = ''
        The goose package to install.

        Defaults to the `default` package exposed by this flake for the
        host system. Set to `null` to skip installing a package (useful
        when goose is installed through another mechanism — for example
        a wrapper derivation — but you still want to manage its
        configuration declaratively).
      '';
    };

    settings = lib.mkOption {
      type = yamlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          GOOSE_PROVIDER = "anthropic";
          GOOSE_MODEL = "claude-sonnet-4-20250514";
          GOOSE_MODE = "smart_approve";

          extensions = {
            developer = {
              enabled = true;
              type = "builtin";
              name = "developer";
            };

            memory = {
              enabled = true;
              type = "stdio";
              name = "memory";
              cmd = "uvx";
              args = [ "mcp-server-memory" ];
              timeout = 300;
            };
          };
        }
      '';
      description = ''
        Free-form attribute set serialised as YAML into goose's
        `config.yaml` (under `$XDG_CONFIG_HOME/goose/`). See goose's
        configuration documentation for the supported keys, including
        `GOOSE_PROVIDER`, `GOOSE_MODEL`, `GOOSE_MODE`, and the
        `extensions` map for MCP server definitions.

        Note: secrets (API keys) are intentionally not handled here.
        Goose reads them from the system keyring or environment
        variables; use `home.sessionVariables`, sops-nix, or an
        equivalent tool for secret material.
      '';
    };

    customProviders = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          llama-swap-local = {
            name = "llama-swap-local";
            engine = "openai";
            display_name = "Local llama-swap";
            api_key_env = "LLAMA_SWAP_API_KEY";
            base_url = "http://localhost:8013/v1/chat/completions";
            models = [
              { name = "qwen3-coder-next"; context_limit = 65536; }
            ];
            supports_streaming = true;
            requires_auth = false;
          };
        }
      '';
      description = ''
        Declarative provider definitions written to
        `$XDG_CONFIG_HOME/goose/custom_providers/<name>.json`. Each
        attribute name becomes the filename (without the `.json`
        suffix) and its value is serialised directly as the provider
        JSON consumed by goose's declarative providers loader.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.package != null) cfg.package;

    xdg.configFile = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        "goose/config.yaml".source = configFile;
      })
      providerFiles
    ];
  };
}
