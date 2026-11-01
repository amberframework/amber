require "file_utils"

module PermissionHelper
  # Whether a read-only directory refuses new files for this process. Root
  # (as in the CircleCI container) ignores directory permissions, so specs
  # that make a directory read-only to force a failed delete are pending
  # there.
  def directory_permissions_enforced? : Bool
    directory = ::File.tempname("amber-permission-probe")
    Dir.mkdir(directory, 0o500)
    begin
      ::File.write(::File.join(directory, "probe"), "")
      false
    rescue ::File::Error
      true
    ensure
      ::File.chmod(directory, 0o700)
      FileUtils.rm_rf(directory)
    end
  end
end
