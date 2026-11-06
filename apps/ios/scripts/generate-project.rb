#!/usr/bin/env ruby
# Generate a complete device-only app. No local credential fixtures are read.
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
source = File.expand_path(ARGV.fetch(0))
configuration = ARGV.fetch(1, 'Debug')
raise 'Configuration must be Debug or Release' unless %w[Debug Release].include?(configuration)
expected = File.read(File.join(__dir__, 'matter-revision.txt')).strip
actual = IO.popen(['git', '-C', source, 'rev-parse', 'HEAD'], &:read).strip
raise 'Wrong Matter source revision' unless actual == expected
framework = File.join(root, '.scratch/MatterFramework/Build/Products', "#{configuration}-iphoneos", 'Matter.framework')
raise 'Build the matching custom framework first' unless File.file?(File.join(framework, 'Headers/MNTNFCReaderBridge.h'))
output = File.join(root, '.scratch/AppProject', configuration)
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'MatterNFCTestTool.xcodeproj'))
project.root_object.project_dir_path = root
target = project.new_target(:application, 'MatterNFCTestTool', :ios, '17.0')
%w[App Sources/NFCProbeCore MatterIntegration].each do |folder|
  group = project.main_group.new_group(folder, File.join(root, folder), '<absolute>')
  Dir.glob(File.join(root, folder, '*.swift')).sort.each do |file|
    target.source_build_phase.add_file_reference(group.new_file(File.basename(file)))
  end
end
framework_ref = project.frameworks_group.new_file(framework)
target.frameworks_build_phase.add_file_reference(framework_ref)
embed = target.new_copy_files_build_phase('Embed Custom Matter Framework')
embed.dst_subfolder_spec = '10'
embed.add_file_reference(framework_ref).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
cert = File.join(source, 'credentials/test/attestation/Chip-Test-PAA-FFF1-Cert.der')
raise 'Public test PAA certificate missing' unless File.file?(cert)
cert_copy = File.join(output, File.basename(cert))
FileUtils.cp(cert, cert_copy)
target.resources_build_phase.add_file_reference(project.main_group.new_file(cert_copy))
# Remove the version-specific Foundation SDK path added by xcodeproj.
project.files.select { |f| f.path.to_s.end_with?('/Foundation.framework') }.each do |ref|
  ref.path = 'System/Library/Frameworks/Foundation.framework'; ref.source_tree = 'SDKROOT'
end
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => ENV.fetch('APP_BUNDLE_ID', 'org.sensereo.matter-nfc-test-tool'),
    'DEVELOPMENT_TEAM' => ENV.fetch('DEVELOPMENT_TEAM', ''),
    'INFOPLIST_FILE' => File.join(root, 'App/Info.plist'),
    'CODE_SIGN_ENTITLEMENTS' => File.join(root, 'App/MatterNFCTest.entitlements'),
    'CODE_SIGN_STYLE' => 'Automatic', 'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1', 'MARKETING_VERSION' => '0.1.0',
    'CURRENT_PROJECT_VERSION' => '1', 'GENERATE_INFOPLIST_FILE' => 'NO',
    'SUPPORTED_PLATFORMS' => 'iphoneos', 'SUPPORTS_MACCATALYST' => 'NO',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc -DMTR_NO_AVAILABILITY=1 -Xcc -DMTR_ENABLE_PROVISIONAL=1',
    'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', File.dirname(framework)],
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
  })
end
# Only the selected configuration is generated, preventing a Release app from
# silently embedding a Debug framework (or the reverse).
[target.build_configuration_list, project.build_configuration_list].each do |list|
  list.build_configurations.reject { |c| c.name == configuration }.each(&:remove_from_project)
  list.default_configuration_name = configuration
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.launch_action.build_configuration = configuration
scheme.archive_action.build_configuration = configuration
scheme.save_as(project.path, 'MatterNFCTestTool', true)
puts project.path
