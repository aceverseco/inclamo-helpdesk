export const captureAvailable = () => Boolean(navigator.mediaDevices?.getDisplayMedia);

export function canvasBlob(canvas, type = 'image/png') {
  return new Promise((resolve, reject) => canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error('image_failed')), type, type === 'image/png' ? undefined : 0.92));
}

// Encoding the drawn pixels drops the image's metadata. A photo keeps a photo
// format: as PNG a JPEG grows several times over, and a file under the
// displayed limit would be refused for our re-encoding. A result still over
// the limit is tried once more as JPEG, on white where it was transparent.
const KEPT_TYPES = ['image/jpeg', 'image/webp'];
export async function encodeImage(canvas, sourceType, maxBytes = Infinity) {
  const blob = await canvasBlob(canvas, KEPT_TYPES.includes(sourceType) ? sourceType : 'image/png');
  if (blob.size <= maxBytes || blob.type === 'image/jpeg') return blob;
  const opaque = document.createElement('canvas');
  try {
    opaque.width = canvas.width;
    opaque.height = canvas.height;
    const context = opaque.getContext('2d');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, opaque.width, opaque.height);
    context.drawImage(canvas, 0, 0);
    return await canvasBlob(opaque, 'image/jpeg');
  } finally {
    opaque.width = 0;
    opaque.height = 0;
  }
}

export const imageName = (name, type) =>
  `${name.replace(/\.[^.]+$/, '')}.${{ 'image/jpeg': 'jpg', 'image/webp': 'webp' }[type] || 'png'}`;

// The chooser is invoked directly from the user's click. No pixels leave this
// module/browser. All tracks stop even when playback, canvas or encoding fails.
export async function captureFrame(beforeFrame = () => {}, afterFrame = () => {}) {
  if (!captureAvailable()) throw new Error('capture_unavailable');
  const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
  const video = document.createElement('video');
  const canvas = document.createElement('canvas');
  let active = true;
  try {
    video.muted = true;
    video.srcObject = stream;
    let timeout;
    let callback;
    try {
      await Promise.race([
        (async () => {
          await video.play();
          if (!active) return;
          await beforeFrame();
          // The first display frame can predate hiding the dialog. Allow the
          // compositor to paint, then read a fresh frame from the capture stream.
          await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
          await new Promise(resolve => setTimeout(resolve, 200));
          if (!active) return;
          if (video.requestVideoFrameCallback) await new Promise(resolve => { callback = video.requestVideoFrameCallback(resolve); });
        })(),
        new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('capture_unavailable')), 10_000); }),
      ]);
    } finally {
      clearTimeout(timeout);
      if (callback !== undefined) video.cancelVideoFrameCallback?.(callback);
    }
    if (!video.videoWidth || !video.videoHeight) throw new Error('capture_unavailable');
    const scale = Math.min(1, Math.sqrt(16_000_000 / (video.videoWidth * video.videoHeight)));
    canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
    canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
    canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
    stream.getTracks().forEach(track => track.stop());
    return await canvasBlob(canvas);
  } finally {
    active = false;
    stream.getTracks().forEach(track => track.stop());
    video.srcObject = null;
    canvas.width = canvas.height = 0;
    afterFrame();
  }
}

export async function flattenImage(blob, maxBytes = Infinity) {
  const bitmap = await createImageBitmap(blob);
  const canvas = document.createElement('canvas');
  try {
    if (bitmap.width * bitmap.height > 40_000_000) throw new Error('image_dimensions');
    const scale = Math.min(1, Math.sqrt(16_000_000 / (bitmap.width * bitmap.height)));
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return await encodeImage(canvas, blob.type, maxBytes);
  } finally { bitmap.close(); canvas.width = canvas.height = 0; }
}
