rm -rf /tmp/vasaro && mkdir /tmp/vasaro && cp -R deployment/osx/vasaro.app /tmp/vasaro && mkdir -p /tmp/vasaro/vasaro.app/Contents/MacOS && cp vasaro /tmp/vasaro/vasaro.app/Contents/MacOS/ && ln -s /Applications /tmp/vasaro/Applications && hdiutil create -volname vasaro -srcfolder /tmp/vasaro -ov -format UDZO /tmp/vasaro.dmg && open /tmp/vasaro.dmg
