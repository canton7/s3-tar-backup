require 'fileutils'

require_relative 'upload_item_failed_error'
require_relative 'backend_object'

module S3TarBackup::Backend
  class FileBackend
    attr_reader :prefix

    def initialize(path)
      @prefix = path
    end

    def name
      "File"
    end

    def remove_item(relative_path)
      File.delete(File.join(@prefix, relative_path))
    end

    def item_exists?(relative_path)
      File.exists?(File.join(@prefix, relative_path))
    end

    def download_item(relative_path, local_path)
      FileUtils.cp(File.join(@prefix, relative_path), local_path)
    end

    def upload_item(relative_path, local_path)
      path = File.join(@prefix, relative_path)
      FileUtils.mkdir_p(File.dirname(path)) unless File.directory?(File.dirname(path))
      FileUtils.cp(local_path, path)
    end

    def list_items(relative_path='')
      return [] unless File.directory?(File.join(@prefix, relative_path))
      relative_path = '.' if relative_path.nil? || relative_path.empty?
      Dir.chdir(@prefix) do
        Dir.entries(relative_path).select{ |x| File.file?(x) }.map do |x|
          path = File.join(relative_path, x)
          BackendObject.new(path, File.size?(path))
        end
      end
    end
  end
end
