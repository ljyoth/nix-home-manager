{ config, lib, pkgs, ... }:

with lib;

let

  stubType = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = "dummy";
        description = "The stub package name.";
      };

      outPath = mkOption {
        type = types.nullOr types.str;
        default = "@${name}@";
        defaultText = literalExpression ''"@''${name}@"'';
      };

      version = mkOption {
        type = types.nullOr types.str;
        default = null;
        defaultText = literalExpression "pkgs.\${name}.version or null";
      };

      buildScript = mkOption {
        type = types.str;
        default = defaultBuildScript;
      };

      extraAttrs = mkOption {
        type = types.attrsOf types.anything;
        default = { };
      };
    };
  });

  defaultBuildScript = "mkdir $out";

  dummyPackage = pkgs.runCommandLocal "dummy" { meta.mainProgram = "dummy"; }
    defaultBuildScript;

  mkStubPackage = { name ? "dummy", outPath ? null, version ? null
    , buildScript ? defaultBuildScript, extraAttrs ? { } }:
    let
      pkg = if name == "dummy" && buildScript == defaultBuildScript then
        dummyPackage
      else
        pkgs.runCommandLocal name {
          pname = name;
          meta.mainProgram = name;
        } buildScript;

      stubbedPkg = pkg // optionalAttrs (outPath != null) {
        inherit outPath;

        # Prevent getOutput from descending into outputs
        outputSpecified = true;

        # Allow the original package to be used in derivation inputs
        __spliced = {
          buildHost = pkg;
          hostTarget = pkg;
        };
      } // optionalAttrs (version != null) { inherit version; } // extraAttrs;
    in stubbedPkg;

in {
  options.test = {
    stubs = mkOption {
      type = types.attrsOf stubType;
      default = { };
      description =
        "Package attributes that should be replaced by a stub package.";
    };

    stubOverlays = mkOption {
      type = types.anything;
      default = [ ];
      internal = true;
    };

    unstubs = mkOption {
      type = types.listOf types.anything;
      default = [ ];
    };
  };

  config = {
    lib.test.mkStubPackage = mkStubPackage;

    test.stubOverlays = [ ] ++ optional (config.test.stubs != { }) (self: super:
      mapAttrs (n: v:
        builtins.traceVerbose "${n} - stubbed" (mkStubPackage (v
          // optionalAttrs (v.version == null) {
            version = super.${n}.version or null;
          }))) config.test.stubs) ++ config.test.unstubs;
  };
}
