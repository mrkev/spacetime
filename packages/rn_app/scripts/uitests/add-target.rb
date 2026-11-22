require 'pathname'
require 'xcodeproj'

# Adds a SpacetimeUITests target to the generated (gitignored) iOS project, compiling every .swift
# file in this folder, and adds it to the Spacetime scheme's tests. Safe to run repeatedly; it has to
# run again after every `expo prebuild --clean`, which regenerates the project without it.
#
# Usage: ruby add-target.rb ios/Spacetime.xcodeproj (run.sh does this for you)

proj_path = File.expand_path(ARGV.fetch(0))
name = 'SpacetimeUITests'
project = Xcodeproj::Project.open(proj_path)
app = project.targets.find { |t| t.name == 'Spacetime' } or abort 'no Spacetime target'
app_settings = app.build_configurations.first.build_settings

target = project.targets.find { |t| t.name == name } ||
         project.new_target(:ui_test_bundle, name, :ios, app_settings['IPHONEOS_DEPLOYMENT_TARGET'])

# The sources stay in the repo; the project points at them, so a prebuild can't delete them.
group = project.main_group.find_subpath(name, true)
sources_dir = __dir__
group.set_source_tree('SOURCE_ROOT')
group.set_path(Pathname.new(sources_dir).relative_path_from(Pathname.new(File.dirname(proj_path))).to_s)
swift_files = Dir.glob('*.swift', base: sources_dir).sort
group.files.reject { |f| swift_files.include?(f.path) }.each do |gone|
  target.source_build_phase.remove_file_reference(gone)
  gone.remove_from_project
end
swift_files.each do |swift|
  file = group.files.find { |f| f.path == swift } || group.new_file(swift)
  unless target.source_build_phase.files_references.include?(file)
    target.source_build_phase.add_file_reference(file, true)
  end
end

target.add_dependency(app) unless target.dependencies.any? { |d| d.target == app }
target.build_configurations.each do |c|
  s = c.build_settings
  s['TEST_TARGET_NAME'] = 'Spacetime'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.mrkev.spacetime.uitests'
  s['SWIFT_VERSION'] = '5.0'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = app_settings['DEVELOPMENT_TEAM']
  s['IPHONEOS_DEPLOYMENT_TARGET'] = app_settings['IPHONEOS_DEPLOYMENT_TARGET']
end
project.save

scheme_path = File.join(Xcodeproj::XCScheme.shared_data_dir(proj_path), 'Spacetime.xcscheme')
scheme = Xcodeproj::XCScheme.new(scheme_path)
unless scheme.test_action.testables.any? { |t| t.buildable_references.any? { |r| r.target_name == name } }
  scheme.test_action.add_testable(Xcodeproj::XCScheme::TestAction::TestableReference.new(target))
end
scheme.save_as(proj_path, 'Spacetime', true)
puts "#{name} target is in #{File.basename(proj_path)}"
