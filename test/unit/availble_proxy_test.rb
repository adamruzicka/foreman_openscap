require 'test_plugin_helper'

class AvailableProxyTest < ActiveSupport::TestCase
  test '#minimum_version should correctly compare versions' do
    api = ProxyAPI::AvailableProxy.new({ url: 'https://something.somewhere.com' })
    ::ProxyAPI::Version.any_instance.expects(:proxy_versions).returns({ 'modules' => { 'openscap' => '0.10.0' }})
    assert api.send(:minimum_version), '0.10.0 is expected to be a higher version that 0.5'
  end
end
