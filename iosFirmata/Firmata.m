//
//  Firmata.m
//  TemperatureSensor
//
//  Created by Jacob on 11/11/13.
//  Copyright (c) 2013 Apple Inc. All rights reserved.
//

#import "Firmata.h"
#import "LeDataService.h"

@interface Firmata()  <LeDataProtocol>{
@private
	BOOL				seenStartSysex;
    id<FirmataProtocol>	peripheralDelegate;
}
@end


@implementation Firmata

@synthesize currentlyDisplayingService;
@synthesize firmataData;


// Place this in the .m file, inside the @implementation block
// A method to convert an enum to string
- (NSString*) pinmodeEnumToString:(PINMODE)enumVal
{
    NSArray *enumArray = [[NSArray alloc] initWithObjects:pinmodeArray];
    return [enumArray objectAtIndex:enumVal];
}


#pragma mark -
#pragma mark Init
/****************************************************************************/
/*								Init										*/
/****************************************************************************/
- (id) initWithService:(LeDataService*)service controller:(id<FirmataProtocol>)controller
{
    self = [super init];
    if (self) {
        firmataData = [[NSMutableData alloc] init];
        seenStartSysex=false;
        
        currentlyDisplayingService = service;
        [currentlyDisplayingService setController:self];
        
        peripheralDelegate = controller;
        
	}
    return self;
}

- (void) dealloc {
    
}

- (void) setController:(id<FirmataProtocol>)controller
{
    peripheralDelegate = controller;
    
}


#pragma mark -
#pragma mark LeData Interactions
/****************************************************************************/
/*                  LeData Interactions                                     */
/****************************************************************************/
- (LeDataService*) serviceForPeripheral:(CBPeripheral *)peripheral
{
    if ( [[currentlyDisplayingService peripheral] isEqual:peripheral] ) {
        return currentlyDisplayingService;
    }
    
    return nil;
}

- (void)didEnterBackgroundNotification:(NSNotification*)notification
{
    NSLog(@"Entered background notification called.");
    [currentlyDisplayingService enteredBackground];
}

- (void)didEnterForegroundNotification:(NSNotification*)notification
{
    NSLog(@"Entered foreground notification called.");
    [currentlyDisplayingService enteredForeground];
    
}


#pragma mark -
#pragma mark Firmata Parsers
/****************************************************************************/
/*				Firmata Parsers                                             */
/****************************************************************************/
/* Receive Firmware Name and Version (after query)
 * 0  START_SYSEX (0xF0)
 * 1  queryFirmware (0x79)
 * 2  major version (0-127)
 * 3  minor version (0-127)
 * 4  first 7-bits of firmware name
 * 5  second 7-bits of firmware name
 * x  ...for as many bytes as it needs)
 * 6  END_SYSEX (0xF7)
 */
- (void) parseReportFirmwareResponse:(NSData*)data
{
    //location 0+1 to ditch start sysex, +1 command byte, +1 major +1 minor
    //length = -1 to kill end sysex, -1 start sysex, -1 command byte -1 major -1 minor =
    NSRange range = NSMakeRange (4, [data length]-5);
    
    unsigned char *bytePtr = (unsigned char *)[data bytes];
    
    NSData *nameData =[data subdataWithRange:range];
    NSString *name = [[NSString alloc] initWithData:nameData encoding:NSASCIIStringEncoding];
    
    [peripheralDelegate didReportFirmware:name major:(unsigned short int)bytePtr[2] minor:(unsigned short int)bytePtr[3]];
}

/* pin state response
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  pin state response (0x6E)
 * 2  pin (0 to 127)
 * 3  pin mode (the currently configured mode)
 * 4  pin state, bits 0-6
 * 5  (optional) pin state, bits 7-13
 * 6  (optional) pin state, bits 14-20
 ...  additional optional bytes, as many as needed
 * N  END_SYSEX (0xF7)
 */
- (void) parsePinStateResponse:(NSData*)data
{
    unsigned char *bytePtr = (unsigned char *)[data bytes];
    [peripheralDelegate didUpdatePin:(int)bytePtr[2] currentMode:(PINMODE)bytePtr[3] value:(unsigned short int)bytePtr[4]];
}

/* analog mapping response
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  analog mapping response (0x6A)
 * 2  analog channel corresponding to pin 0, or 127 if pin 0 does not support analog
 * 3  analog channel corresponding to pin 1, or 127 if pin 1 does not support analog
 * 4  analog channel corresponding to pin 2, or 127 if pin 2 does not support analog
 ...   etc, one byte for each pin
 * N  END_SYSEX (0xF7)
 */
- (void) parseAnalogMappingResponse:(NSData*)data
{
    //argue we dont need analog if we have capability
}

/* capabilities response
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  capabilities response (0x6C)
 * 2  1st mode supported of pin 0
 * 3  1st mode's resolution of pin 0
 * 4  2nd mode supported of pin 0
 * 5  2nd mode's resolution of pin 0
 ...   additional modes/resolutions, followed by a single 127 to mark the
 end of the first pin's modes.  Each pin follows with its mode and
 127, until all pins implemented.
 * N  END_SYSEX (0xF7)
 */
- (void) parseCapabilityResponse:(NSData*)data
 {
     
     NSMutableArray *pins = [[NSMutableArray alloc] init];
     
     const char *bytes = [data bytes];
     //start at 2 to ditch start and command byte
     //take end byte off the end
     for (int i = 2; i < [data length] - 1; i++)
     {
         //ugh altering i inside of loop...
         NSMutableDictionary *modes = [[NSMutableDictionary alloc] init];

         while(bytes[i]!=127){

             const char *mode = bytes[i++];
             const char *resolution = bytes[i++];
             
             NSLog(@"%02hhx,%02hhx", mode, resolution);
             
             [modes setObject:[NSNumber numberWithChar:resolution] forKey:[NSNumber numberWithChar:mode]];
             
         }
     
         //end of pin
         NSMutableDictionary *pin = [[NSMutableDictionary alloc] init];
         //[pin setObject:0 forKey:@"value"];
         [pin setObject:modes forKey:@"modes"];
         [pins addObject:pin];
     }
     NSLog(@"%@",pins);

     [peripheralDelegate didUpdateCapability:(NSMutableArray*)pins];
 }


#pragma mark -
#pragma mark Firmata Delegate Methods
/****************************************************************************/
/*				Firmata Delegate Methods                                    */
/****************************************************************************/
/* Query Firmware Name and Version
 * 0  START_SYSEX (0xF0)
 * 1  queryFirmware (0x79)
 * 2  END_SYSEX (0xF7)
 */
- (void) reportFirmware
{
    const unsigned char bytes[] = {START_SYSEX, REPORT_FIRMWARE, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"reportFirmware bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* write to servo, servo write is performed if the pins mode is SERVO
 * ------------------------------
 * 0  ANALOG_MESSAGE (0xE0-0xEF)
 * 1  value lsb
 * 2  value msb
 */
- (void) analogMessagePin:(int)pin value:(unsigned short int)value
{
    const unsigned char bytes[] = {START_SYSEX, ANALOG_MESSAGE + pin, value, value>>4, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"analogMessagePin bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* two byte digital data format, second nibble of byte 0 gives the port number (e.g. 0x92 is the third port, port 2)
 * 0  digital data, 0x90-0x9F, (MIDI NoteOn, but different data format)
 * 1  digital pins 0-6 bitmask
 * 2  digital pin 7 bitmask
 */
- (void) digitalMessagePin:(int)pin value:(unsigned short int)value
{
    const unsigned char bytes[] = {START_SYSEX, DIGITAL_MESSAGE + pin, value , value>>4, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"digitalMessagePin bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* request version report
 * 0  request version report (0xF9) (MIDI Undefined)
 */
- (void) reportAnalog:(int)pin enable:(BOOL)enable
{
    const unsigned char bytes[] = {START_SYSEX, REPORT_ANALOG + pin, enable, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"reportAnalog bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* toggle digital port reporting by port (second nibble of byte 0), e.g. 0xD1 is port 1 is pins 8 to 15,
 * 0  toggle digital port reporting (0xD0-0xDF) (MIDI Aftertouch)
 * 1  disable(0)/enable(non-zero)
 */
- (void) reportDigital:(int)pin enable:(BOOL)enable
{
    const unsigned char bytes[] = {START_SYSEX, REPORT_DIGITAL + pin, enable, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"reportDigital bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* set pin mode
 * 1  set digital pin mode (0xF4) (MIDI Undefined)
 * 2  pin number (0-127)
 * 3  state (INPUT/OUTPUT/ANALOG/PWM/SERVO, 0/1/2/3/4)
 */
- (void) setPinMode:(int)pin mode:(PINMODE)mode
{
    const unsigned char bytes[] = {START_SYSEX, SET_PIN_MODE, pin, mode, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];
 
    NSLog(@"setPinMode bytes in hex: %@", [dataToSend description]);

    [currentlyDisplayingService write:dataToSend];
}

/* analog mapping query
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  analog mapping query (0x69)
 * 2  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
 */
- (void) analogMappingQuery
{
    const unsigned char bytes[] = {START_SYSEX, ANALOG_MAPPING_QUERY, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"analogMappingQuery bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* capabilities query
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  capabilities query (0x6B)
 * 2  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
 */
- (void) capabilityQuery
{
    const unsigned char bytes[] = {START_SYSEX, CAPABILITY_QUERY, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"capabilityQuery bytes in hex: %@", [dataToSend description]);

    [currentlyDisplayingService write:dataToSend];
}

/* pin state query
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  pin state query (0x6D)
 * 2  pin (0 to 127)
 * 3  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
 */
- (void) pinStateQuery:(int)pin
{
    const unsigned char bytes[] = {START_SYSEX, PIN_STATE_QUERY, pin, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"pinStateQuery bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];

}

/* servo config
 * --------------------
 * 0  START_SYSEX (0xF0)
 * 1  SERVO_CONFIG (0x70)
 * 2  pin number (0-127)
 * 3  minPulse LSB (0-6)
 * 4  minPulse MSB (7-13)
 * 5  maxPulse LSB (0-6)
 * 6  maxPulse MSB (7-13)
 * 7  END_SYSEX (0xF7)
 */
- (void) servoConfig:(int)pin minPulse:(unsigned short int)minPulse maxPulse:(unsigned short int)maxPulse
{
    const unsigned char bytes[] = {START_SYSEX, SERVO_CONFIG, pin, minPulse, minPulse>>4, maxPulse, maxPulse>>4, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"servoConfig bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* I2C config
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  I2C_CONFIG (0x78)
 * 2  Delay in microseconds (LSB)
 * 3  Delay in microseconds (MSB)
 * ... user defined for special cases, etc
 * n  END_SYSEX (0xF7)
 */
- (void) i2cConfig:(unsigned short int)delay data:(NSData *)data{

    const unsigned char first[] = {START_SYSEX, I2C_CONFIG, delay, delay>>4};
    const unsigned char second[] = {END_SYSEX};
    
    NSMutableData *dataToSend = [[NSMutableData alloc] initWithBytes:first length:sizeof(first)];
    [dataToSend appendData:data];
    [dataToSend appendBytes:second length:sizeof(second)];

    NSLog(@"i2cConfig bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}

/* I2C read/write request
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  I2C_REQUEST (0x76)
 * 2  slave address (LSB)
 * 3  slave address (MSB) + read/write and address mode bits
 {7: always 0} + {6: reserved} + {5: address mode, 1 means 10-bit mode} +
 {4-3: read/write, 00 => write, 01 => read once, 10 => read continuously, 11 => stop reading} +
 {2-0: slave address MSB in 10-bit mode, not used in 7-bit mode}
 * 4  data 0 (LSB)
 * 5  data 0 (MSB)
 * 6  data 1 (LSB)
 * 7  data 1 (MSB)
 * ...
 * n  END_SYSEX (0xF7)
 */
- (void) i2cRequest:(I2CMODE)i2cMode address:(unsigned short int)address data:(NSData *)data{
    
    const unsigned char first[] = {START_SYSEX, I2C_REQUEST, address, i2cMode};
    NSMutableData *dataToSend = [[NSMutableData alloc] initWithBytes:first length:sizeof(first)];
    [dataToSend appendData:data];
    const unsigned char second[] = {END_SYSEX};
    [dataToSend appendBytes:second length:sizeof(second)];
    
    NSLog(@"i2cRequest bytes in hex: %@", [dataToSend description]);

    [currentlyDisplayingService write:dataToSend];
}

/* extended analog
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  extended analog message (0x6F)
 * 2  pin (0 to 127)
 * 3  bits 0-6 (least significant byte)
 * 4  bits 7-13
 * ... additional bytes may be sent if more bits needed
 * N  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
 */
//- (void) extendedAnalogQuery:(int)pin:] withData:(NSData)data{
//    const unsigned char bytes[] = {START_SYSEX, EXTENDED_ANALOG, pin, END_SYSEX};
//    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

//    NSLog(@"extendedAnalogQuery bytes in hex: %@", [dataToSend description]);

//
//    [currentlyDisplayingService write:dataToSend];
//}

//- (void) stringData:(NSString)string{
//    const unsigned char bytes[] = {START_SYSEX, STRING_DATA, pin, END_SYSEX};
//    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

//    NSLog(@"stringData bytes in hex: %@", [dataToSend description]);

//
//    [currentlyDisplayingService write:dataToSend];
//}

//- (void) shiftData:(int)high{
//    const unsigned char bytes[] = {START_SYSEX, SHIFT_DATA, pin, END_SYSEX};
//    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

//    NSLog(@"shiftData bytes in hex: %@", [dataToSend description]);
//
//    [currentlyDisplayingService write:dataToSend];
//}


/* Set sampling interval
 * -------------------------------
 * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
 * 1  SAMPLING_INTERVAL (0x7A)
 * 2  sampling interval on the millisecond time scale (LSB)
 * 3  sampling interval on the millisecond time scale (MSB)
 * 4  END_SYSEX (0xF7)
 */
- (void) samplingInterval:(unsigned short int)intervalMilliseconds
{
    const unsigned char bytes[] = {START_SYSEX, SAMPLING_INTERVAL, intervalMilliseconds, intervalMilliseconds>>4, END_SYSEX};
    NSData *dataToSend = [[NSData alloc] initWithBytes:bytes length:sizeof(bytes)];

    NSLog(@"samplingInterval bytes in hex: %@", [dataToSend description]);
    
    [currentlyDisplayingService write:dataToSend];
}


#pragma mark -
#pragma mark LeDataProtocol Delegate Methods
/****************************************************************************/
/*				LeDataProtocol Delegate Methods                             */
/****************************************************************************/
/** Received data */
- (void) serviceDidReceiveData:(NSData*)data fromService:(LeDataService*)service
{
    
    if (service != currentlyDisplayingService)
        return;
    
//    unsigned char mockHex[] = {0xf0,0x90,0x20,0x20,0x20,0xf7};
//    NSData *mock = [NSData dataWithBytes:mockHex length:6];
    
    //parse of our (up to) 20 bytes
    //may or may not be a whole (or a single) command
    const unsigned char *bytes = [data bytes];
    for (int i = 0; i < [data length]; i++)
    {
        const unsigned char byte = bytes[i];
        NSLog(@"Processing %02hhx", byte);

        if(!seenStartSysex && byte==START_SYSEX)
        {
            NSLog(@"Start sysex received, clear data");
            [firmataData setLength:0];
            [firmataData appendBytes:( const void * )&byte length:1];
            seenStartSysex=true;
        
        }else if(seenStartSysex && byte==END_SYSEX)
        {
            [firmataData appendBytes:( const void * )&byte length:1];
            
            NSLog(@"End sysex received");
            seenStartSysex=false;
            
            const unsigned char *firmataDataBytes = [firmataData bytes];
            NSLog(@"Control byte is %02hhx", firmataDataBytes[1]);
            
            switch ( firmataDataBytes[1] )
            {

                case ANALOG_MAPPING_RESPONSE:
                    [self parseAnalogMappingResponse:firmataData];
                    break;
                
                case CAPABILITY_RESPONSE:
                    [self parseCapabilityResponse:firmataData];
                    break;
                    
                case PIN_STATE_RESPONSE:
                    [self parsePinStateResponse:firmataData];
                    break;

                case ANALOG_MESSAGE:
                    NSLog(@"type of message is anlog");
                    break;
                    
                case REPORT_FIRMWARE:
                    NSLog(@"type of message is firmware report");
                    [self parseReportFirmwareResponse:firmataData];
                    break;
                    
                case REPORT_VERSION:
                    NSLog(@"type of message is version report");
                    break;
                    
                default:
                    NSLog(@"type of message unknown");
                    break;
            }
        }else{
            [firmataData appendBytes:( const void * )&byte length:1];
        }
    }
}

/** Central Manager reset */
- (void) serviceDidReset
{
    NSLog(@"Service reset");
    //TODO do something? probably have to go back to root controller and reconnect?
}

/** Peripheral connected or disconnected */
- (void) serviceDidChangeStatus:(LeDataService*)service
{
    
    //TODO do something?
    if ( [[service peripheral] isConnected] ) {
        NSLog(@"Service (%@) connected", service.peripheral.name);
    }
    
    else {
        NSLog(@"Service (%@) disconnected", service.peripheral.name);
        
    }
}


@end