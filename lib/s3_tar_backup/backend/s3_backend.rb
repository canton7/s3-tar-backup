require 'aws-sdk'

require_relative 'upload_item_failed_error'
require_relative 'backend_object'

module S3TarBackup::Backend
  class S3Backend
    attr_reader :prefix

    @s3

    def initialize(access_key, secret_key, region, dest_prefix)
      warn "No AWS region specified (config key settings.s3_region). Assuming eu-west-1" unless region
      @s3 = AWS::S3.new(access_key_id: access_key, secret_access_key: secret_key, region: region || 'eu-west-1')
      @prefix = dest_prefix
    end

    def name
      "S3"
    end

    def remove_item(relative_path)
      bucket, path = parse_bucket_object("#{@prefix}/#{relative_path}")
      @s3.buckets[bucket].objects[path].delete
    end

    def item_exists?(relative_path)
      bucket, path = parse_bucket_object("#{@prefix}/#{relative_path}")
      @s3.buckets[bucket].objects[path].exists?
    end

    def download_item(relative_path, local_path)
      bucket, path = parse_bucket_object("#{@prefix}/#{relative_path}")
      object = @s3.buckets[bucket].objects[path]
      open(local_path, 'wb') do |f|
        object.read do |chunk|
          f.write(chunk)
        end
      end
    end

    def upload_item(relative_path, local_path, remove_original)
      bucket, path = parse_bucket_object("#{@prefix}/#{relative_path}")
      @s3.buckets[bucket].objects.create(path, Pathname.new(local_path))
      File.delete(local_path) if remove_original
    rescue Errno::ECONNRESET => e
      raise UploadItemFailedError.new, e.message
    end

    def list_items(relative_path='')
      bucket, path = parse_bucket_object("#{@prefix}/#{relative_path}")
      @s3.buckets[bucket].objects.with_prefix(path).map do |x|
        BackendObject.new(x.key, x.content_length)
      end
    end

  private
    def parse_bucket_object(path)
      path.split('/', 2)
    end
  end
end