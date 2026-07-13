{
  description = "Weekly launchd snapshots of the macOS call history database (phone + FaceTime)";

  # The module only uses the consumer's pkgs/lib — no inputs needed.
  outputs = { self }: {
    darwinModules.default = import ./nix/darwin.nix;
  };
}
