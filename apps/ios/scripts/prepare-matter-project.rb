#!/usr/bin/env ruby
# Create a disposable Xcode project; leave the pinned upstream checkout untouched.
require 'fileutils'
require 'xcodeproj'

app_root = File.expand_path('..', __dir__)
source = File.expand_path(ARGV.fetch(0))
framework_root = File.join(source, 'src/darwin/Framework')
output = File.join(app_root, '.scratch/MatterBridgeProject')
project_path = File.join(output, 'Matter.xcodeproj')
FileUtils.mkdir_p(project_path)
FileUtils.cp(File.join(framework_root, 'Matter.xcodeproj/project.pbxproj'), project_path)

project = Xcodeproj::Project.open(project_path)
project.root_object.project_dir_path = framework_root
target = project.targets.find { |t| t.name == 'Matter' }
raise 'Pinned framework target not found' unless target

bridge_dir = File.join(app_root, 'MatterIntegration')
group = project.main_group.new_group('NFC Test Bridge', bridge_dir, '<absolute>')
header = group.new_file('MNTNFCReaderBridge.h')
target.headers_build_phase.add_file_reference(header).settings = { 'ATTRIBUTES' => ['Public'] }
target.source_build_phase.add_file_reference(group.new_file('MNTNFCReaderBridge.mm'))

# Extend the umbrella header only in the generated project.
umbrella = File.join(output, 'Matter.h')
File.write(umbrella, File.read(File.join(framework_root, 'CHIP/Matter.h')) + "\n#import <Matter/MNTNFCReaderBridge.h>\n")
ref = project.files.find { |f| File.basename(f.path.to_s) == 'Matter.h' }
raise 'Pinned umbrella header not found' unless ref
ref.path = umbrella
ref.source_tree = '<absolute>'

project.build_configurations.each do |config|
  config.build_settings['CHIP_ROOT'] = source
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.save_as(project.path, 'NFC Matter Framework', true)
puts project_path
