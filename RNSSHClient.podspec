require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name             = 'RNSSHClient'
  s.version          = package['version']
  s.summary          = package['description']
  s.license          = package['license']
  s.homepage         = package['homepage']
  s.authors          = package['author']['name']
  s.source           = { :git => package['repository']['url'], :tag => s.version }
  s.source_files     = 'ios/*.swift'
  s.requires_arc     = true
  # 18.0 (bumped from 17.0): the Citadel/NIOTransportServices bridge in RNSSHClientDeps needs
  # SE-0417 task executor preference (withTaskExecutorPreference), which requires the iOS 18
  # Concurrency runtime - see the comment on EventLoopTaskExecutor in RNSSHClientDeps.swift.
  s.platforms        = { :ios => "18.0" }
  s.swift_version    = '5.9'

  # Built at publish time by scripts/build-ios-xcframework.sh, wrapping Citadel - see
  # ios/XCFrameworkBuild. Not committed to git; shipped in the npm tarball like lib/ is.
  s.vendored_frameworks = 'ios/RNSSHClientDeps.xcframework'

  # RNSSHClientDeps.xcframework is a static-library-style xcframework (`-library` + `-headers`,
  # not a `.framework` bundle), so Xcode only wires its Headers dir into the Clang (-Xcc -I)
  # search path, not Swift's own module search path - `import RNSSHClientDeps` can't resolve
  # without this. Xcode's own xcframework handling resolves each pod's headers per
  # platform/configuration under .../Products/<config>/XCFrameworkIntermediates/<pod>/Headers,
  # a directory up from $(BUILT_PRODUCTS_DIR) as CocoaPods sets it for a pod target (that
  # points at .../Products/<config>/<pod>, this pod's own product subdirectory).
  s.pod_target_xcconfig = {
    'SWIFT_INCLUDE_PATHS' => '$(inherited) $(BUILT_PRODUCTS_DIR)/../XCFrameworkIntermediates/RNSSHClient/Headers'
  }

  s.dependency 'ExpoModulesCore'
end
