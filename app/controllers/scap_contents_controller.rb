class ScapContentsController < ApplicationController
  include Foreman::Controller::AutoCompleteSearch
  include Foreman::Controller::Parameters::ScapContent

  before_action :find_by_id, :only => %i[show edit update destroy]

  def model_of_controller
    ::ForemanOpenscap::ScapContent
  end

  def index
    @contents = resource_base_search_and_page.search_for(params[:search])
  end

  def show
    send_data @scap_content.scap_file,
              :type     => 'application/xml',
              :filename => @scap_content.original_filename
  end

  def new
    @scap_content = ForemanOpenscap::ScapContent.new
  end

  def create
    @scap_content = ForemanOpenscap::ScapContent.new(scap_content_params.except(:scap_file))
    attach_scap_file
    if @scap_content.save
      process_success
    else
      process_error
    end
  end

  def update
    @scap_content.assign_attributes(scap_content_params.except(:scap_file))
    attach_scap_file
    if @scap_content.save
      process_success
    else
      process_error
    end
  end

  def destroy
    if @scap_content.destroy
      process_success
    else
      process_error :object => @scap_content
    end
  end

  private

  def find_by_id
    @scap_content = resource_base.find(params[:id])
  end

  def attach_scap_file
    return unless params[:scap_content] && (raw_file = params[:scap_content][:scap_file])

    if raw_file.respond_to?(:tempfile)
      @scap_content.attach_scap_file(raw_file.tempfile, :filename => raw_file.original_filename)
    else
      filename = params[:scap_content][:original_filename] || "#{@scap_content.title}.xml"
      @scap_content.attach_scap_file(StringIO.new(raw_file.to_s), :filename => filename)
    end
  end
end
