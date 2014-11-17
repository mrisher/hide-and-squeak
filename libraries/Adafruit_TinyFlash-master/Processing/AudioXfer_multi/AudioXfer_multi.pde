// WAV file converter for Trinket audio project.  Works with
// 'AudioLoader' sketch on Arduino w/Winbond flash chip.
// For Processing 2.0; will not work in 1.5!

import processing.serial.*;

Serial  port = null;
int     capacity;
boolean done = false;

// Wait for line from serial port, with timeout
String readLine() {
  String s;
  int    start = millis();
  do {
    s = port.readStringUntil('\n');
  } while((s == null) && ((millis() - start) < 3000));
  return s;
}

// Extract unsigned multibyte value from byte array
int uvalue(byte b[], int offset, int len) {
  int    i, x, result = 0;
  byte[] bytes = java.util.Arrays.copyOfRange(b, offset, offset + len);
  for(i=0; i<len; i++) {
    x = bytes[i];
    if(x < 0) x += 256;
    result += x << (i * 8);
  }
  return result;
}

void setup() {
  String s;

  size(200, 200); // Serial freaks out without a window :/

  // Locate Arduino running AudioLoader sketch.
  // Try each serial port, checking for ACK after opening.
  println("Scanning serial ports...");
  for(String portname : Serial.list()) {
    try {
      portname = "/dev/cu.usbserial-A6008hRq";  // bypass scan
      port = new Serial(this, portname, 57600);
    } catch (Exception e) { // Port in use, etc.
      continue;
    }
    print("Trying port " + portname + "...");
    if(((s = readLine()) != null) && s.contains("HELLO")) {
      println("OK");
      break;
    } else {
      println();
      port.stop();
      port = null;
    }
  }

  if(port != null) { // Find one?
    if(((s        = readLine())                != null)
    && ((capacity = Integer.parseInt(s.trim())) > 0)) {
      println("Found Arduino w/" + capacity + " byte flash chip.");
      selectFolder("Select a folder full of wav files to process:", "fileSelected");
    } else {
      println("Arduino failed to initialize flash memory.");
      done = true;
    }
  } else {
    println("Could not find connected Arduino running AudioLoader sketch.");
    done = true;
  }
}

void fileSelected(File f) {
  if(f == null) {
    println("Cancel selected or window closed.");
  } else {
    File files[] = f.listFiles(new java.io.FilenameFilter() {
      public boolean accept(File directory, String fileName) {
        return fileName.endsWith(".wav");
      }
    });
    println("Selected files: " + files.length);
  
    port.write("ERASE"); // Issue erase command now, process audio while it works
    
    int masterSampleRate = -1;
    
    // Load each matching file into an array, then write it to Flash
    for (int file=0; file < files.length; file++)
    {
      String filename = files[file].getAbsolutePath();
      println("Selected file: " + filename);
      byte input[] = loadBytes(filename);

      // Check for a few 'magic words' in the file
      if(java.util.Arrays.equals(java.util.Arrays.copyOfRange(input, 0, 4 ),     "RIFF".getBytes())
      && java.util.Arrays.equals(java.util.Arrays.copyOfRange(input, 8, 16), "WAVEfmt ".getBytes())
      && (uvalue(input, 20, 2) == 1) ) {
        int chunksize  = uvalue(input, 16, 4),
            channels   = uvalue(input, 22, 2),
            rate       = uvalue(input, 24, 4),
            bitsPer    = uvalue(input, 34, 2),
            bytesPer   = uvalue(input, 32, 2),
            bytesTotal = uvalue(input, 24+chunksize, 4),
            samples    = bytesTotal / bytesPer;
  
      if (masterSampleRate == -1)
        masterSampleRate = rate;
      else if (masterSampleRate != rate)
        println("ERROR: " + filename + " sample rate should be same as others, i.e. " + masterSampleRate + ".\n");
  
        println("Processing sound file " + filename + "...\n"
        + "  " + channels + " channel(s)\n"
        + "  " + rate     + " Hz\n" +
          "  " + bitsPer  + " bits\n" +
          "  " + samples  + " samples\n");
  
        // truncate file (TODO: Update for Multi-mode to avoid overrunning capacity)
        // if(samples > (capacity - 6)) samples = capacity - 6;
        
        byte[] output;
        int headerOffset = 0;
        if (file == 0) {                   // For first file, write special header
          headerOffset = 3;                // with 3 extra bytes (rate(2) + num files)
          output = new byte[samples + headerOffset + 4];
          output[0] = (byte)(rate >> 8);     // Sampling rate (Hz)
          output[1] = (byte)(rate);
          output[2] = (byte)(files.length);
        } else {
          output = new byte[samples + 4];
        }
        output[headerOffset] = (byte)(samples >> 24); // Number of samples
        output[headerOffset+1] = (byte)(samples >> 16);
        output[headerOffset+2] = (byte)(samples >> 8);
        output[headerOffset+3] = (byte)(samples);
  
        int index_in = chunksize + 28, index_out = headerOffset+4, end = samples + index_out;
        int c, lo, hi, sum, div;
  
        // Merge channels, convert to 8-bit
        if(bitsPer == 16) div = (channels * 256);
        else              div =  channels;
        while(index_out < end) {
          sum = 0;
          for(c=0; c<channels; c++) {
            if(bitsPer == 8) {
              lo = input[index_in++];
              if(lo < 0) lo += 256;
              sum += lo;
            } else if(bitsPer == 16) {
              lo = input[index_in++];
              if(lo < 0) lo += 256;
              hi = input[index_in++];
              sum += (hi + 128) * 256 + lo;
            }
          }
          output[index_out++] = (byte)(sum / div);
        }
        
        if (file == 0) {
          print("Erasing flash..."); // Really just waiting for the erase ACK
          String s;
          while(((s = readLine()) == null) || (s.contains("READY") == false));
        }
        
        print("OK\nWriting " + filename + "...");
        // Instead of just write(output), it's done per-byte so we
        // can echo progress dots from the Arduino to the console.
        // Eventually may want to make it re-write error sectors.
        for(int i=0; i<output.length; i++) {
          port.write(output[i]);
          if((c = port.read()) >= 0) print((char)c);
        }
        println("done!");
      } else {
        println("Invalid WAV file.");
      }
    }
  }
  done = true;
  println("All finished.\n");
}

void draw() {
  if(done) exit();
}

