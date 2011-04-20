//
//  EveDownload.m
//  MacEFT
//
//  Created by ugo pozo on 3/30/11.
//  Copyright 2011 Netframe. All rights reserved.
//

#import "EveDownload.h"


@implementation EveDownloadInfo

@synthesize URL, error, expectedLength, receivedLength, result, connection;

- (id)initWithURLString:(NSString *) url {
	if ((self = [super init])) {
		[self setURL:url];

		[self setError:nil];
		[self setResult:nil];

		[self setExpectedLength:0L];
		[self setReceivedLength:0L];
		
		[self setConnection:nil];
	}
	
	return self;
}

- (NSData *)data {
	return [NSData dataWithData:[self result]];
}

- (void)dealloc {
	[self setURL:nil];
	[self setError:nil];
	[self setResult:nil];
	[self setConnection:nil];
	
	[super dealloc];
}

@end


@implementation EveDownload

@synthesize downloads, expectedLength, receivedLength, delegate;

- (id)initWithURLList:(NSDictionary *)urls {
	NSMutableDictionary * d;
	NSString * name, * strURL;
	EveDownloadInfo * info;
	
	if ((self = [super init])) {
		d = [[NSMutableDictionary alloc] initWithCapacity:10];
		
		for (name in [urls allKeys]) {
			strURL = [urls objectForKey: name];
			info   = [[EveDownloadInfo alloc] initWithURLString:strURL];
			
			[d setObject:info forKey:name];
			
			[info release];
		}
		
		non_finished = 0;
		
		downloads = [[NSDictionary alloc] initWithDictionary:d];
		[d release];
	}
	
	return self;
}

- (void)start {
	NSURLRequest * request;
	NSURLConnection * connection;
	NSURL * url;
	EveDownloadInfo * info;
	
	non_finished = (unsigned) [downloads count];
	
	for (info in [downloads allValues]) {
		url        = [NSURL URLWithString:[info URL]];
		request    = [[NSURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30.0];
		connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
		
		[info setConnection:connection];
		[info setResult:[NSMutableData data]];
		
		[connection start];
		
		[connection release];
		[request release];
	}
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	EveDownloadInfo * info;
	NSHTTPURLResponse * httpResponse;
	NSError * error;
	NSDictionary * errorInfo;
	NSString * errorDesc;
	long statusCode;
	
	statusCode = -1;
	
	if ([response respondsToSelector:@selector(statusCode)]) {
		httpResponse = (NSHTTPURLResponse *) response;
		statusCode   = [httpResponse statusCode];

		if (statusCode >= 400) {
			[connection cancel];
			
			errorDesc = [NSString stringWithFormat:@"Server returned status code %d", statusCode];
			errorInfo = [NSDictionary dictionaryWithObject:errorDesc forKey:NSLocalizedDescriptionKey];
			error     = [NSError errorWithDomain:@"HTTPError" code:statusCode userInfo:errorInfo];

			[self connection:connection didFailWithError:error];
		}
	}
	
	if (statusCode < 400) {
		info = [self infoForConnection:connection];
		
		if ([response expectedContentLength] != NSURLResponseUnknownLength) {
			[info setExpectedLength:((uint64_t) [response expectedContentLength])];
			[self setExpectedLength:([self expectedLength] + [response expectedContentLength])];
		}
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	EveDownloadInfo * info;
	
	info = [self infoForConnection:connection];
	
	[[info result] appendData:data];
	[info setReceivedLength:([info receivedLength] + [data length])];
	[self setReceivedLength:([self receivedLength] + [data length])];
	
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[self downloadFinished:connection withError:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[self downloadFinished:connection withError:nil];
}

- (void)downloadFinished:(NSURLConnection *)connection withError:(NSError *)error {
	EveDownloadInfo * info;
	NSData * data;
	NSString * key;
	
	info = [self infoForConnection:connection];
	data = (error) ? nil : [info data];
	key  = [[downloads allKeysForObject:info] objectAtIndex:0];

	[info setError:error];
	
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(didFinishDownload:forKey:withData:error:)]) {
		[[self delegate] didFinishDownload:self forKey:key withData:data error:error];
	}
	
	non_finished--;
	
	if ([self delegate] && !non_finished)
		[[self delegate] didFinishDownload:self withResults:[self results]];
}

- (void)addObserver:(NSObject *)anObserver {
	NSString * keyPath, * key;
	
	keyPath = @"downloads.%@.%@";
	
	[self addObserver:anObserver forKeyPath:@"expectedLength" \
			  options:NSKeyValueObservingOptionNew context:self];

	[self addObserver:anObserver forKeyPath:@"receivedLength" \
			  options:NSKeyValueObservingOptionNew context:self];

	
	for (key in [downloads allKeys]) {
		[self addObserver:anObserver forKeyPath:[NSString stringWithFormat:keyPath, key, @"expectedLength"] \
				  options:NSKeyValueObservingOptionNew context:self];

		[self addObserver:anObserver forKeyPath:[NSString stringWithFormat:keyPath, key, @"receivedLength"] \
				  options:NSKeyValueObservingOptionNew context:self];
	}
}

- (void)removeObserver:(NSObject *)anObserver {
	NSString * keyPath, * key;
	
	keyPath = @"downloads.%@.%@";

	[self removeObserver:anObserver forKeyPath:@"expectedLength"];
	[self removeObserver:anObserver forKeyPath:@"receivedLength"];
	
	
	for (key in [downloads allKeys]) {
		[self removeObserver:anObserver forKeyPath:[NSString stringWithFormat:keyPath, key, @"expectedLength"]];
		[self removeObserver:anObserver forKeyPath:[NSString stringWithFormat:keyPath, key, @"receivedLength"]];
	}
}

- (EveDownloadInfo *)infoForConnection:(NSURLConnection *)connection {
	EveDownloadInfo * info, * cursor;
	
	info = nil;
	
	for (cursor in [downloads allValues]) {
		if ([cursor connection] == connection) {
			info = cursor;
			break;
		}
	}
	
	return info;
}


- (void)dealloc {
	[downloads release];
	
	[super dealloc];
}

- (NSDictionary *)results {
	NSMutableDictionary * results;
	NSDictionary * retval, * data;
	NSString * key;
	NSError * error;
	EveDownloadInfo * info;
	
	results = [[NSMutableDictionary alloc] init];
	
	for (key in [downloads allKeys]) {
		info  = [downloads objectForKey:key];
		error = [info error];
		
		data  = [[NSDictionary alloc] initWithObjectsAndKeys: \
				 (error) ? [NSNull null] : [info data], @"data", \
				 (error) ? error : [NSNull null], @"error", \
				 nil];
		
		[results setValue:data forKey:key];
		
		[data release];
	}
	
	retval = [NSDictionary dictionaryWithDictionary:results];
	
	[results release];
	
	return retval;
}

@end



