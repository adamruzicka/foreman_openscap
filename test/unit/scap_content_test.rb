require 'test_plugin_helper'

class ScapContentTest < ActiveSupport::TestCase
  setup do
    @scap_file = File.new("#{ForemanOpenscap::Engine.root}/test/files/scap_contents/ssg-fedora-ds.xml", 'rb').read
  end

  def build_scap_content(title = 'Fedora', contents = @scap_file, filename = 'ssg-fedora-ds.xml')
    scap_content = ForemanOpenscap::ScapContent.new(:title => title)
    scap_content.attach_scap_file(StringIO.new(contents), :filename => filename)
    scap_content
  end

  context 'validate scap contents' do
    test 'create scap content' do
      scap_content = build_scap_content
      assert(scap_content.valid?)
    end

    test 'reads a pending attachment before it is committed' do
      scap_content = build_scap_content

      assert_equal @scap_file, scap_content.scap_file_contents
    end

    test 'stores the file in ActiveStorage' do
      scap_content = build_scap_content
      assert scap_content.save

      assert scap_content.scap_file.attached?
      assert_equal @scap_file, scap_content.scap_file_contents
      assert_equal 'ssg-fedora-ds.xml', scap_content.original_filename
    end

    test 'fails validation without an attached file' do
      scap_content = ForemanOpenscap::ScapContent.new(:title => 'Fedora')

      assert_not scap_content.valid?
      assert_includes scap_content.errors[:scap_file], "can't be blank"
    end

    test 'updates the digest when the attachment changes' do
      scap_content = build_scap_content
      assert scap_content.save
      original_digest = scap_content.digest

      replacement = File.read("#{ForemanOpenscap::Engine.root}/test/files/scap_contents/cs9-old/ssg-cs9-ds.xml", :mode => 'rb')
      scap_content.attach_scap_file(StringIO.new(replacement), :filename => 'ssg-cs9-ds.xml')
      assert scap_content.save

      assert_not_equal original_digest, scap_content.digest
    end

    test 'should not allow title.length > 255' do
      scap_content = build_scap_content("a" * 256)
      assert_not(scap_content.valid?)
    end

    test 'scap content should fail if no openscap proxy' do
      SmartProxy.stubs(:with_features).returns([])
      scap_content = build_scap_content
      assert_not(scap_content.save)
      assert_includes(scap_content.errors.messages[:base], 'No proxy with OpenSCAP feature was found.')
    end

    test 'proxy_url should return the first available proxy it finds' do
      available_proxy = SmartProxy.with_features('Openscap').first
      unavailable_proxy = FactoryBot.create(:smart_proxy, :url => 'http://proxy.example.com:8443', :features => [FactoryBot.create(:feature, :name => 'Openscap')])
      SmartProxy.expects(:with_features).with('Openscap').returns([unavailable_proxy, available_proxy])
      SmartProxy.any_instance.expects(:ping).twice.returns(false).then.returns(true)
      scap_content = build_scap_content
      assert_equal(available_proxy.url, scap_content.proxy_url)
    end
  end

  test 'should update profile title when fetching profiles from proxy' do
    scap_content = FactoryBot.create(:scap_content)
    scap_content.stubs(:fetch_profiles).returns({ "xccdf.test.profile" => "Changed title" })
    scap_profile = FactoryBot.create(:scap_content_profile, :scap_content => scap_content, :profile_id => 'xccdf.test.profile', :title => "Original title")
    scap_content.create_profiles
    assert_equal scap_profile.reload.title, 'Changed title'
  end

  test 'should create profile when fetching profiles from proxy' do
    scap_content = FactoryBot.create(:scap_content)
    scap_content.stubs(:fetch_profiles).returns({ "xccdf.test.profile" => "My title" })
    scap_content.create_profiles
    assert scap_content.reload.scap_content_profiles.where(:title => 'My title').first
  end
end
