Pod::Spec.new do |s|
  s.name                  = "OrigamiEngine"
  s.version               = "1.0.14"
  s.summary               = "Lightweight iOS/OSX audio engine with flac, cue, mp3, m4a, m3u support."
  s.homepage              = "https://github.com/leshkoapps/OrigamiEngine.git"
  s.license               = 'MIT'
  s.author                = { "ap4y" => "lod@pisem.net" }
  s.source                = { :git => "https://github.com/leshkoapps/OrigamiEngine.git", :submodules => true }
  s.default_subspec       = 'Core'
  s.requires_arc          = false
  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'

  s.subspec 'Core' do |core|
      core.source_files          = 'OrigamiEngine/*.{h,m}', 'OrigamiEngine/Plugins/{CoreAudio,Cue,File,HTTP,M3U}*.{h,m}'
      core.ios.frameworks        = 'AudioToolbox', 'AVFoundation'
      core.osx.frameworks        = 'AudioToolbox', 'AVFoundation', 'AudioUnit'
  end

  s.subspec 'Flac' do |flac|
      flac.dependency 'OrigamiEngine/Core'

      # flac.source_files          = 'OrigamiEngine/Plugins/FlacDecoder.{h,m}'
      # flac.frameworks            = 'Flac'
      #
      # flac.ios.preserve_paths    = 'Audio-Frameworks/bin/flac/FLAC.framework'
      # flac.ios.xcconfig          = { 'FRAMEWORK_SEARCH_PATHS' => '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/flac/"' }
      #
      # flac.osx.preserve_paths    = 'Audio-Frameworks/bin/flac/Flac_OSX/FLAC.framework'
      # flac.osx.xcconfig          = { 'FRAMEWORK_SEARCH_PATHS' => '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/flac/FLAC_OSX"' }
	  
	  flac.source_files            = 'OrigamiEngine/Plugins/FlacDecoder.{h,m}', 'Audio-Frameworks/libogg-src/src/bitwise.c', 'Audio-Frameworks/libogg-src/src/framing.c', 'Audio-Frameworks/flac-src/src/libFLAC/bitmath.c', 'Audio-Frameworks/flac-src/src/libFLAC/bitreader.c', 'Audio-Frameworks/flac-src/src/libFLAC/bitwriter.c', 'Audio-Frameworks/flac-src/src/libFLAC/cpu.c', 'Audio-Frameworks/flac-src/src/libFLAC/crc.c', 'Audio-Frameworks/flac-src/src/libFLAC/fixed.c', 'Audio-Frameworks/flac-src/src/libFLAC/float.c', 'Audio-Frameworks/flac-src/src/libFLAC/format.c', 'Audio-Frameworks/flac-src/src/libFLAC/lpc.c', 'Audio-Frameworks/flac-src/src/libFLAC/md5.c', 'Audio-Frameworks/flac-src/src/libFLAC/memory.c', 'Audio-Frameworks/flac-src/src/libFLAC/metadata_iterators.c', 'Audio-Frameworks/flac-src/src/libFLAC/metadata_object.c', 'Audio-Frameworks/flac-src/src/libFLAC/ogg_decoder_aspect.c', 'Audio-Frameworks/flac-src/src/libFLAC/ogg_encoder_aspect.c', 'Audio-Frameworks/flac-src/src/libFLAC/ogg_helper.c', 'Audio-Frameworks/flac-src/src/libFLAC/ogg_mapping.c', 'Audio-Frameworks/flac-src/src/libFLAC/stream_decoder.c', 'Audio-Frameworks/flac-src/src/libFLAC/stream_encoder_framing.c', 'Audio-Frameworks/flac-src/src/libFLAC/stream_encoder.c', 'Audio-Frameworks/flac-src/src/libFLAC/window.c', 'Audio-Frameworks/libogg-src/include/ogg/ogg.h', 'Audio-Frameworks/libogg-src/include/ogg/os_types.h', 'Audio-Frameworks/FLAC/config.h', 'Audio-Frameworks/flac-src/include/FLAC/all.h', 'Audio-Frameworks/flac-src/include/FLAC/assert.h', 'Audio-Frameworks/flac-src/include/FLAC/callback.h', 'Audio-Frameworks/flac-src/include/FLAC/export.h', 'Audio-Frameworks/flac-src/include/FLAC/format.h', 'Audio-Frameworks/flac-src/include/FLAC/metadata.h', 'Audio-Frameworks/flac-src/include/FLAC/ordinals.h', 'Audio-Frameworks/flac-src/include/FLAC/stream_decoder.h', 'Audio-Frameworks/flac-src/include/FLAC/stream_encoder.h'
  	  flac.library 				   = 'c++'
  	  flac.xcconfig 			   = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++14', 'CLANG_CXX_LIBRARY' => 'libc++', 'HEADER_SEARCH_PATHS' => [
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/flac-src/include/"',
			  '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/flac-src/include/FLAC/"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/libogg-src/include/"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/flac-src/src/libFLAC/include/"'
          ].join(' ') }
  end

  s.subspec 'Opus' do |opus|
      opus.dependency 'OrigamiEngine/Core'

      opus.source_files          = 'OrigamiEngine/Plugins/OpusFileDecoder.{h,m}'
      opus.frameworks            = 'Ogg', 'Opus', 'OpusFile'

      opus.ios.preserve_paths    = [
          'Audio-Frameworks/bin/ogg/Ogg.framework',
          'Audio-Frameworks/bin/opus/Opus.framework',
          'Audio-Frameworks/bin/opusfile/OpusFile.framework',
          'Audio-Frameworks/bin/opus/include',
      ]
      opus.ios.xcconfig          = {
          'FRAMEWORK_SEARCH_PATHS' => [
              '"$(SDKROOT)/Developer/Library/Frameworks"',
              '"$(DEVELOPER_LIBRARY_DIR)/Frameworks"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/ogg/"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/opus/"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/opusfile/"'
          ].join(' '),
          'HEADER_SEARCH_PATHS' => '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/opus/include"'
      }

      opus.osx.preserve_paths    = [
          'Audio-Frameworks/bin/ogg/Ogg.framework',
          'Audio-Frameworks/bin/ogg/MacOS/Ogg.framework',
          'Audio-Frameworks/bin/opus/MacOS/Opus.framework',
          'Audio-Frameworks/bin/opusfile/MacOS/OpusFile.framework'
      ]
      opus.osx.xcconfig          = {
          'FRAMEWORK_SEARCH_PATHS' => [
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/ogg/MacOS"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/opus/MacOS"',
              '"$(PODS_ROOT)/OrigamiEngine/Audio-Frameworks/bin/opusfile/MacOS"'
          ].join(' ')
      }
  end

end
