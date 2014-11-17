// Audio playback sketch for Adafruit Trinket.  Requires 3.3V
// Trinket board and Winbond W25Q80BV serial flash loaded with
// audio data.  PWM output on pin 4; add ~25 KHz low-pass filter
// prior to amplification.  Uses ATtiny-specific registers;
// WILL NOT RUN ON OTHER ARDUINOS.

#include <Adafruit_TinyFlash.h>
#include <util/delay.h>

#if(F_CPU == 16000000L)
#error "Compile for 8 MHz Trinket"
#endif

const int MAX_CLIPS=10;
const int MASTER_HEADER=3;      // Number of bytes at top of chip
const int CLIP_HEADER=4;        // Number of bytes at top of each clip

Adafruit_TinyFlash flash;
uint16_t           sample_rate, delay_count;
uint8_t            num_clips;
uint32_t           clip_starts[MAX_CLIPS];
uint32_t           clip_samples[MAX_CLIPS];
volatile uint32_t  index = 0L;
volatile uint8_t   current_clip = 0;

void setup() {
  uint8_t  data[MASTER_HEADER + CLIP_HEADER];
  uint32_t bytes;

  if(!(bytes = flash.begin())) {     // Flash init error?
    for(;; PORTB ^= 2, delay(250));  // Blink 2x/sec
  }

  // First three bytes contain sample rate, number of clips
  flash.beginRead(0);
  for(uint8_t i=0; i<MASTER_HEADER; i++) 
    data[i] = flash.readNextByte();
  sample_rate = ((uint16_t)data[0] <<  8)
              |  (uint16_t)data[1];
  num_clips   = (uint8_t)data[2];
  
  for(uint8_t clip=0; clip<num_clips && clip<MAX_CLIPS; clip++) {
      
    // The start of the 1st clip is CLIP_HEADER + MASTER_HEADER
    // The start of the nth clip is start(n-1) + length(n-1) + CLIP_HEADER
    clip_starts[clip] = CLIP_HEADER + (clip == 0 ? MASTER_HEADER : clip_starts[clip-1] + clip_samples[clip-1]);

    // Now read the sample size for this clip
    for(uint8_t i=0; i<CLIP_HEADER; i++) 
      data[i] = flash.readNextByte();
    clip_samples[clip] = ((uint32_t)data[0] << 24)
                      | ((uint32_t)data[1] << 16)
                      | ((uint32_t)data[2] <<  8)
                      |  (uint32_t)data[3];

    flash.beginRead(clip_starts[clip] + clip_samples[clip]);
  }
  
  // Seek to first byte of first sample
  flash.beginRead(MASTER_HEADER + CLIP_HEADER);

  PLLCSR |= _BV(PLLE);               // Enable 64 MHz PLL
  delayMicroseconds(100);            // Stabilize
  while(!(PLLCSR & _BV(PLOCK)));     // Wait for it...
  PLLCSR |= _BV(PCKE);               // Timer1 source = PLL

  // Set up Timer/Counter1 for PWM output
  TIMSK  = 0;                        // Timer interrupts OFF
  TCCR1  = _BV(CS10);                // 1:1 prescale
  GTCCR  = _BV(PWM1B) | _BV(COM1B1); // PWM B, clear on match
  OCR1C  = 255;                      // Full 8-bit PWM cycle
  OCR1B  = 127;                      // 50% duty at start

  pinMode(4, OUTPUT);                // Enable PWM output pin

  // Set up Timer/Counter0 for sample-playing interrupt.
  // TIMER0_OVF_vect is already in use by the Arduino runtime,
  // so TIMER0_COMPA_vect is used.  This code alters the timer
  // interval, making delay(), micros(), etc. useless (the
  // overflow interrupt is therefore disabled).

  // Timer resolution is limited to either 0.125 or 1.0 uS,
  // so it's rare that the playback rate will precisely match
  // the data, but the difference is usually imperceptible.
  TCCR0A = _BV(WGM01) | _BV(WGM00);  // Mode 7 (fast PWM)
  if(sample_rate >= 31250) {
    TCCR0B = _BV(WGM02) | _BV(CS00); // 1:1 prescale
    OCR0A  = ((F_CPU + (sample_rate / 2)) / sample_rate) - 1;
  } else {                           // Good down to about 3900 Hz
    TCCR0B = _BV(WGM02) | _BV(CS01); // 1:8 prescale
    OCR0A  = (((F_CPU / 8L) + (sample_rate / 2)) / sample_rate) - 1;
  }
  TIMSK = _BV(OCIE0A); // Enable compare match, disable overflow
}

void loop() { }

ISR(TIMER0_COMPA_vect) {
  OCR1B = flash.readNextByte();                              // Read flash, write PWM reg.
  if(++index >= clip_samples[current_clip]) {                // End of audio data?
    index = 0;                                               // We must repeat!
    flash.endRead();
    current_clip = random(10); // TODO: should be num_clips);                        // Select a new clip
//    When the user request delay which exceed the maximum possible one,
//    _delay_ms() provides a decreased resolution functionality. In this
//    mode _delay_ms() will work with a resolution of 1/10 ms, providing
//    delays up to 6.5535 seconds (independent from CPU frequency).  The
//    user will not be informed about decreased resolution.
    int delays = random(3,5);
    for (int d=0; d < delays; d++)
      _delay_ms(10000);                                       // Use new delay library to pause n * 6.5535 sec.
    flash.beginRead(clip_starts[current_clip]);              // Skip 6 byte header
  }
}

