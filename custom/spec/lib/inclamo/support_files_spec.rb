# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Support::Files do
  # Pixel noise: detail that, like a photo's, a lossless format cannot shrink.
  def noise(width, height)
    bands = Array.new(3) { Vips::Image.gaussnoise(width, height, mean: 128, sigma: 40) }
    bands.first.bandjoin(bands.drop(1)).cast(:uchar)
  end

  def pixels(bytes)
    Vips::Image.new_from_buffer(bytes, '')
  end

  it 'keeps a photo under the displayed limit a JPEG, without its metadata or anything appended to it' do
    photo = noise(500, 500).copy
    photo.set_type(GObject::GSTR_TYPE, 'exif-ifd0-Artist', 'Synthetic Photographer')
    bytes = photo.write_to_buffer('.jpg', Q: 92)
    limit = 500_000
    stub_const('Inclamo::Support::MAX_BYTES', limit)
    # As PNG the same pixels are over the limit: the old rewrite refused this photo.
    expect(bytes.bytesize).to be < limit
    expect(photo.write_to_buffer('.png').bytesize).to be > limit
    expect(pixels(bytes).get_fields).to include('exif-data')

    safe = described_class.validate!("#{bytes}<script>appended()</script>", filename: 'IMG_0042.JPG')

    expect(safe).to include(type: 'image/jpeg', filename: 'IMG_0042.jpg')
    expect(safe[:bytes].bytesize).to be <= limit
    expect(safe[:bytes]).not_to include('appended')
    expect(pixels(safe[:bytes]).get_fields.grep(/exif/)).to be_empty
  end

  it 'keeps a PNG a PNG' do
    bytes = Vips::Image.black(40, 20).cast(:uchar).write_to_buffer('.png')

    expect(described_class.validate!(bytes, filename: 'screen.png')).to include(type: 'image/png', filename: 'screen.png')
  end

  it 'writes an image its own format would take past the limit as a JPEG, on white where it was transparent' do
    opaque = Vips::Image.black(300, 300).draw_rect(255, 0, 0, 150, 300, fill: true).cast(:uchar)
    bytes = noise(300, 300).bandjoin(opaque).write_to_buffer('.png')
    stub_const('Inclamo::Support::MAX_BYTES', bytes.bytesize)
    allow(described_class).to receive(:save_image).and_wrap_original do |original, image, type|
      type == 'image/png' ? 'x' * (bytes.bytesize + 1) : original.call(image, type)
    end

    safe = described_class.validate!(bytes, filename: 'diagram.png')

    expect(safe).to include(type: 'image/jpeg', filename: 'diagram.jpg')
    expect(safe[:bytes].bytesize).to be <= bytes.bytesize
    expect(pixels(safe[:bytes]).getpoint(250, 10)).to eq([255.0, 255.0, 255.0])
  end

  it 'refuses an image that is over the limit in every form' do
    # A 16-colour PNG: small as sent, larger in full colour and as a JPEG.
    opaque = Vips::Image.black(300, 300).draw_rect(255, 0, 0, 150, 300, fill: true).cast(:uchar)
    bytes = noise(300, 300).bandjoin(opaque).write_to_buffer('.png', palette: true, colours: 16)
    stub_const('Inclamo::Support::MAX_BYTES', bytes.bytesize + 1_000)

    expect { described_class.validate!(bytes, filename: 'palette.png') }.to raise_error(Inclamo::Support::Invalid, 'file_size')
  end
end
