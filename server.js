// ============================================================
//
// Page Stuff
//
// ============================================================

const $ = document.querySelector.bind(document);

let dither_factor = 0.9;

$('#dither').addEventListener('input', e => {
  const input = e.target;
  dither_factor = (input.value - input.min) / (input.max - input.min);
});

let hires_buffer = new Uint8Array(8192);

// Save the last captured frame as a hires image file.
$('#save').addEventListener('click', e => {
  const blob = new Blob([hires_buffer], {type: 'application/octet-stream'});
  const anchor = document.createElement('a');
  anchor.download = 'image.bin';
  anchor.href = URL.createObjectURL(blob);
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(anchor.href);
});

// Start capturing the desktop.
let interval_id;
$('#start').addEventListener('click', async e => {
  clearInterval(interval_id);

  try {
    const mediaStream = await navigator.getDisplayMedia({video:true});
    const vid = document.createElement('video');
    vid.srcObject = mediaStream;
    vid.play();

    const quant = $('#quant');
    const qctx = quant.getContext('2d');

    const can = document.createElement('canvas');
    can.width = quant.width;
    can.height = quant.height;
    const ctx = can.getContext('2d');
    ctx.imageSmoothingQuality = 'high';

    const indexes = new Array(can.width * can.height);

    interval_id = setInterval(() => {
      ctx.drawImage(vid, 0, 0, can.width, can.height);

      const imagedata = ctx.getImageData(0, 0, can.width, can.height);

      quantize(imagedata, indexes);
      convert_to_hires(indexes, hires_buffer);

      qctx.putImageData(imagedata, 0, 0);

    }, 500);

  } catch (e) {
    alert('getDisplayMedia support or access denied');
    return;
  }

  startStreaming();
});

// ============================================================
//
// Image Stuff
//
// ============================================================

const palette = [
  /* Black1 */ [0x00, 0x00, 0x00],
  /* Green  */ [0x2f, 0xbc, 0x1a],
  /* Violet */ [0xd0, 0x43, 0xe5],
  /* White1 */ [0xff, 0xff, 0xff],
  /* Black2 */ [0x00, 0x00, 0x00],
  /* Orange */ [0xd0, 0x6a, 0x1a],
  /* Blue   */ [0x2f, 0x95, 0xe5],
  /* White2 */ [0xff, 0xff, 0xff]
];

// Distance in 3-space
function distance(r1,g1,b1,r2,g2,b2) {
  const dr = r1 - r2;
  const dg = g1 - g2;
  const db = b1 - b2;
  return  Math.sqrt(dr*dr + dg*dg + db*db);
}

function quantize(imagedata, indexes) {
  const hash = {};
  for (let i = 0; i < palette.length; ++i) {
    const entry = palette[i];
    const rgb = (entry[0] << 16) | (entry[1] << 8) | entry[2];
    hash[rgb] = i;
  }

  // Floyd-Steinberg
  function offset(x, y) {
    return 4 * (x + y * imagedata.width);
  }

  function err(x, y, er, eg, eb) {
    if (x < 0 || x >= imagedata.width || y < 0 || y >= imagedata.height)
      return;
    const i = offset(x, y);
    const data = imagedata.data;
    data[i + 0] += er;
    data[i + 1] += eg;
    data[i + 2] += eb;
  }

  const data = imagedata.data;
  for (let y = 0; y < imagedata.height; ++y) {
    for (let x = 0; x < imagedata.width; ++x) {
      const i = offset(x, y);

      const r = data[i];
      const g = data[i+1];
      const b = data[i+2];

      // Find closest in palette.
      const rgb = (r << 16) | (g << 8) | b;
      let index = hash[rgb];
      if (index === undefined) {
        let dist;
        for (let p = 0; p < palette.length; ++p) {
          const entry = palette[p];
          const d = distance(r,g,b, entry[0], entry[1], entry[2]);
          if (dist === undefined || d < dist) {
            dist = d;
            index = p;
          }
        }
        hash[rgb] = index;
      }
      const pi = palette[index];

      // Calculate error
      let err_r = (data[i] - pi[0]);
      let err_g = (data[i+1] - pi[1]);
      let err_b = (data[i+2] - pi[2]);

      // Arbitrary damping factor to reduce noise at the cost of
      // fidelity.
      err_r *= dither_factor;
      err_g *= dither_factor;
      err_b *= dither_factor;

      // Update pixel
      data[i] = pi[0];
      data[i+1] = pi[1];
      data[i+2] = pi[2];

      indexes[i / 4] = index;

      // Distribute error
      err(x + 1, y,     err_r * 7/16, err_g * 7/16, err_b * 7/16);
      err(x - 1, y + 1, err_r * 3/16, err_g * 3/16, err_b * 3/16);
      err(x,     y + 1, err_r * 5/16, err_g * 5/16, err_b * 5/16);
      err(x + 1, y + 1, err_r * 1/16, err_g * 1/16, err_b * 1/16);
    }
  }
}

// Scan line mapping table for Apple II Hi-Res screen.
// Index into the array is the y-coordinate. The value
// in the array is the offset (in bytes) from the
// start of the hi-res screen buffer to the start of the
// scan line. The scan line itself is 40 bytes wide.
const OFFSETS = [
  0x0000,0x0400,0x0800,0x0c00,0x1000,0x1400,0x1800,0x1c00,
  0x0080,0x0480,0x0880,0x0c80,0x1080,0x1480,0x1880,0x1c80,
  0x0100,0x0500,0x0900,0x0d00,0x1100,0x1500,0x1900,0x1d00,
  0x0180,0x0580,0x0980,0x0d80,0x1180,0x1580,0x1980,0x1d80,
  0x0200,0x0600,0x0a00,0x0e00,0x1200,0x1600,0x1a00,0x1e00,
  0x0280,0x0680,0x0a80,0x0e80,0x1280,0x1680,0x1a80,0x1e80,
  0x0300,0x0700,0x0b00,0x0f00,0x1300,0x1700,0x1b00,0x1f00,
  0x0380,0x0780,0x0b80,0x0f80,0x1380,0x1780,0x1b80,0x1f80,
  0x0028,0x0428,0x0828,0x0c28,0x1028,0x1428,0x1828,0x1c28,
  0x00a8,0x04a8,0x08a8,0x0ca8,0x10a8,0x14a8,0x18a8,0x1ca8,
  0x0128,0x0528,0x0928,0x0d28,0x1128,0x1528,0x1928,0x1d28,
  0x01a8,0x05a8,0x09a8,0x0da8,0x11a8,0x15a8,0x19a8,0x1da8,
  0x0228,0x0628,0x0a28,0x0e28,0x1228,0x1628,0x1a28,0x1e28,
  0x02a8,0x06a8,0x0aa8,0x0ea8,0x12a8,0x16a8,0x1aa8,0x1ea8,
  0x0328,0x0728,0x0b28,0x0f28,0x1328,0x1728,0x1b28,0x1f28,
  0x03a8,0x07a8,0x0ba8,0x0fa8,0x13a8,0x17a8,0x1ba8,0x1fa8,
  0x0050,0x0450,0x0850,0x0c50,0x1050,0x1450,0x1850,0x1c50,
  0x00d0,0x04d0,0x08d0,0x0cd0,0x10d0,0x14d0,0x18d0,0x1cd0,
  0x0150,0x0550,0x0950,0x0d50,0x1150,0x1550,0x1950,0x1d50,
  0x01d0,0x05d0,0x09d0,0x0dd0,0x11d0,0x15d0,0x19d0,0x1dd0,
  0x0250,0x0650,0x0a50,0x0e50,0x1250,0x1650,0x1a50,0x1e50,
  0x02d0,0x06d0,0x0ad0,0x0ed0,0x12d0,0x16d0,0x1ad0,0x1ed0,
  0x0350,0x0750,0x0b50,0x0f50,0x1350,0x1750,0x1b50,0x1f50,
  0x03d0,0x07d0,0x0bd0,0x0fd0,0x13d0,0x17d0,0x1bd0,0x1fd0
];

const SCREEN_WIDTH = 280;
const SCREEN_WIDTH_COLOR = SCREEN_WIDTH/2;
const SCREEN_HEIGHT = 192;
const PIXEL_BITS_PER_BYTE = 7;

function convert_to_hires(indexes, buffer) {

  for (let y = 0; y < SCREEN_HEIGHT; ++y) {
    let hbas = OFFSETS[y];
    let hidx = y * SCREEN_WIDTH_COLOR;

    // Process two bytes at a time (20 per scan line) since pixel patterns
    // repeat every two bytes (7 color pixels).
    for (let pair = 0; pair < (SCREEN_WIDTH_COLOR / PIXEL_BITS_PER_BYTE); ++pair) {
      // Count the pixels in each "palette"; the most votes wins the byte
      let pal1 = 0; // count of "palette 1" (green/violet) pixels
      let pal2 = 0; // count of "palette 2" (orange/blue) pixels

      // Accumulate the pixel bit-pairs into accum at offset
      let accum = 0;
      let offset = 0;

      for (let pixel = 0; pixel < PIXEL_BITS_PER_BYTE; ++pixel) {
        const index = indexes[hidx++];
        let bits = 0;

        // Note that pixels are in "reverse" order
        switch (index) {
        case 0: bits = 0; break;
        case 1: bits = 2; ++pal1; break;
        case 2: bits = 1; ++pal1; break;
        case 3: bits = 3; break;
        case 4: bits = 0; break;
        case 5: bits = 2; ++pal2; break;
        case 6: bits = 1; ++pal2; break;
        case 7: bits = 3; break;
        default:
          throw new Error(`Invalid palette index: ${index} ${y}`);
        }

        accum |= ( bits << offset );
        offset += 2;

        // bits:   01234560123456
        // pixels: 00112233445566

        // NOTE: This is a poor approximation and doesn't account for white
        // emerging from any two adjacent lit bits and other NTSC fun.

        if (pixel == 3 || pixel == 6) {
          // emit byte
          let b = accum & 0x7f;
          accum >>= 7;
          offset = 1;

          if (pal2 > pal1)
            b |= 0x80;

          buffer[hbas] = b;
          hbas++;

          pal1 = 0;
          pal2 = 0;
        }
      }
    }
  }
}

// ============================================================
//
// Serial Stuff
//
// ============================================================

let port;

$('#bootstrap').addEventListener('click', async e => {

  alert('On the Apple II, type:\n\n' +
        '  IN#2                 (then press Return)\n' +
        '  Ctrl+A 14B       (then press Return)\n\n' +
        'Then click OK');

  const CLIENT_ADDR = 0x6000;
  const CLIENT_FILE = 'client/client.bin';

  port = getSerialPort();

  await port.write('CALL -151'); // Enter Monitor

  const response = await fetch(CLIENT_FILE);
  if (!response.ok)
    throw new Error(response.statusText);
  const bytes = new Uint8Array(await response.arrayBuffer());
  let addr = CLIENT_ADDR;
  for (let offset = 0; offset < bytes.length; offset += 8) {
    const str = addr.toString(16).toUpperCase() + ': ' +
            [...bytes.slice(offset, offset + 8)]
            .map(b => ('00' + b.toString(16).toUpperCase()).substr(-2))
            .join(' ');

    await port.write(str);
  }

  await port.write('\x03'); // Ctrl+C - Exit Monitor
  await port.write(`CALL ${CLIENT_ADDR}`); // Execute client


  const splash = await fetch('res/SPLASH.PIC.BIN');
  if (!splash.ok)
    throw new Error(response.statusText);
  await port.write(new Uint8Array(await splash.arrayBuffer()));
});


async function getSerialPort() {

  const ports = await SerialPort.requestPorts();
  if (!ports.length) throw new Error('No ports');
  const port = new SerialPort(ports[0].path);

  const reader = port.in.getReader();
  const writer = port.out.getWriter();

  // Generator yielding one byte at a time from |reader|.
  const gen = (async function*() {
    while (true) {
      const {value, done} = await reader.read();
      if (done) return;
      for (const byte of value)
        yield byte;
    }
  })();

  return {
    // Read N bytes from port, returns plain array.
    read: async function read(n) {
      if (n <= 0) throw new Error();
      const result = [];
      for await (const byte of gen) {
        result.push(byte);
        if (--n === 0) break;
      }
      return result;
    },

    // Write Uint8Array of bytes to port.
    write: async function(bytes) {
      await writer.write(bytes);
    },

    // Close port.
    close: async function() {
      await writer.close();
    }
  };
}

// ============================================================
//
// Protocol Implementation
//
// ============================================================

async function startStreaming() {

  const state = {
    keyboard: 0,

    button0: 0,
    button1: 0,

    paddle0: 0,
    paddle1: 0,

    mousex: 0,
    mousey: 0,
    mousebtn: 0
  };


  while (true) {
    const command = await port.read(1)[0];
    const size = await port.read(1)[0];
    const data = size ? await port.read(size) : [];

    switch (command) {

      // Keyboard
    case 0x00: state.keyboard = data[0]; break;

      // Buttons
    case 0x10: state.buttom0 = data[0]; break;
    case 0x11: state.button1 = data[0]; break;

      // Paddles
    case 0x20: state.paddle0 = data[0]; break;
    case 0x21: state.paddle0 = data[0]; break;

      // Mouse
    case 0x30: state.mousex = data[0] | (data[1] << 8); break;
    case 0x31: state.mousey = data[0] | (data[1] << 8); break;
    case 0x32: state.mousebtn = data[0]; break;

      // Screen
    case 0x80: port.write(hires_buffer); break;

    default:
      console.warn(`Unexpected protocol command: ${command}`);
    }
  }
}
