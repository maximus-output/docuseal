# frozen_string_literal: true

class EmbedScriptsController < ActionController::Metal
  def show
    filename = params[:filename]
    manifest_path = Rails.public_path.join('packs', 'manifest.json')

    if manifest_path.exist?
      manifest = JSON.parse(manifest_path.read)
      pack_key = manifest.keys.find { |k| k == "js/#{filename}" || k.start_with?("js/#{filename.sub(/\.js$/, '')}-") }

      if pack_key
        relative_path = pack_key.sub(%r{^js/}, '')
        js_path = Rails.public_path.join('packs', relative_path)

        if js_path.exist?
          headers['Content-Type'] = 'application/javascript'
          headers['Cache-Control'] = 'public, max-age=86400'
          self.response_body = js_path.read
          self.status = 200
          return
        end
      end
    end

    self.response_body = ''
    self.status = 404
  end
end
