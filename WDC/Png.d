module wdc.png;

import std.zlib, std.stdio,
       wdc.car;

static class Png
{
	static uint[256] crcTable;

	public static ubyte[] wdcTextureToPng(Colour[] palette, ubyte[] texture, uint width, uint height)
	{
		assert(width <= 0xFF && height <= 0xFF, "Given texture size unhandled by wdc.Png");

		ubyte[] result = [137, 'P', 'N', 'G', 13, 10, 26, 10];
		ubyte[] pngHeader = [0, 0, 0, 0xD,
		                     'I', 'H', 'D', 'R',
		                     0, 0, 0, cast(ubyte)width,
		                     0, 0, 0, cast(ubyte)height,
		                     4, 3, 0, 0, 0];
		pngHeader ~= getCrc(pngHeader[4..$]);
		result ~= pngHeader;

		ubyte[] outputPalette = [0, 0, 0, 48, 'P', 'L', 'T', 'E'];
		ubyte[] outputAlphas = [0, 0, 0, 16, 't', 'R', 'N', 'S'];
		
		foreach (index, colour; palette)
		{
			outputPalette ~= cast(ubyte)(colour.r * 8);
			outputPalette ~= cast(ubyte)(colour.g * 8);
			outputPalette ~= cast(ubyte)(colour.b * 8);
			outputAlphas ~= index == 0 ? 0 : 0xFF;
		}
		
		outputPalette ~= getCrc(outputPalette[4..$]);
		outputAlphas ~= getCrc(outputAlphas[4..$]);

		result ~= outputPalette;
		result ~= outputAlphas;

		ubyte[] idat = [0, 0, 0, 0, 'I', 'D', 'A', 'T'];
		ubyte[] idatData = [];
		foreach_reverse (y; 0..height)
		{
			idatData ~= 0; // filter
			foreach (x; 0..(width / 2))
			{
				idatData ~= texture[(y * (width / 2)) + x];
			}
		}
		idat ~= compress(idatData);
		uint idatDataSize = idat.length - 8;
		assert(idatDataSize <= 0xFFFF, "PNG too big for me buas");
		idat[2] = (idatDataSize >> 8) & 0xFF;
		idat[3] = idatDataSize & 0xFF;
		idat ~= getCrc(idat[4..$]);
		result ~= idat;

		ubyte[] credit = [0, 0, 0, 30, 't', 'E', 'X', 't', 'a', 'u', 't', 'h', 'o', 'r', 0,
		                  'W', 'D', 'C', 'B', 'u', 't', 'c', 'h', 'e', 'r', ' ',
		                  'b', 'y', ' ', 'J', 'a', 'y', 't', 'h', 'e', 'H', 'a', 'm'];
		credit ~= getCrc(credit[4..$]);
		result ~= credit;
		ubyte[] iend = [0,0,0,0, 'I', 'E', 'N', 'D'];
		iend ~= getCrc(iend[4..$]);
		result ~= iend;
		return result;
	}

	private static ubyte[] getCrc(ubyte[] stream, uint crc = 0)
	{
		uint c;
		if (crcTable[1] == 0)
		{
			foreach (n; 0..256)
			{
				c = n;
				foreach (k; 0..8)
				{
					if ((c & 1) == 1)
					{
						c = 0xEDB88320 ^ ((c >> 1) & 0x7FFFFFFF);
					}
					else
					{
						c = ((c >> 1) & 0x7FFFFFFF);
					}
				}
				crcTable[n] = c;
			}
		}
		c = crc ^ 0xffffffff;
		foreach(piece; stream)
		{
			c = crcTable[(c ^ piece) & 255] ^ ((c >> 8) & 0xFFFFFF);
		}
		c = c ^ 0xffffffff;
		return [(c >> 24) & 0xff, (c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff];
	}

	public static ubyte[] pngToWdcTexture(string filePath)
	{
		import std.string, std.bitmanip, std.file;
		ubyte[] texture;
		if (exists(filePath))
		{
			File input = File(filePath, "rb");
			assert(input.rawRead(new ubyte[4]) == [137, 'P', 'N', 'G'], format("%s not recognised as a PNG file.", filePath));

			input.seek(8);
			uint chunkSize = peek!uint(input.rawRead(new ubyte[4]));
			input.seek(0x10);
			uint width = peek!uint(input.rawRead(new ubyte[4]));
			uint height = peek!uint(input.rawRead(new ubyte[4]));
			
			assert(input.rawRead(new ubyte[1])[0] == 4, "Unsupported Bit Depth");
			assert(input.rawRead(new ubyte[1])[0] == 3, "Unsupported Colour Type");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Compression method");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Filter Type");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Interlacing");

			uint position = chunkSize + 20;
			ubyte[4] chunkName;
			while (true)
			{
				input.seek(position);
				chunkSize = peek!uint(input.rawRead(new ubyte[4]));
				input.rawRead(chunkName);

				if (chunkName == ['I','D','A','T'])
				{
					ubyte[] idat = input.rawRead(new ubyte[chunkSize]);
					ubyte[] rawData = cast(ubyte[])uncompress(idat);
					uint byteNum = 0;
					foreach_reverse (y; 0..height)
					{
						byteNum += 1; // filter
						foreach (x; 0..(width / 2))
						{
							texture ~= rawData[byteNum];
							byteNum += 1;
						}
					}
				}
				else if (chunkName == ['I','E','N','D'])
				{
					break;
				}

				position += chunkSize + 12;
			}
			input.close();
		}
		else
		{
			writeln("File not found: ", filePath);
		}
		return texture;
	}

	public static Colour[] pngToWdcPalette(string filePath)
	{
		import std.string, std.bitmanip, std.file;
		Colour[] palette;
		if (exists(filePath))
		{
			File input = File(filePath, "rb");
			assert(input.rawRead(new ubyte[4]) == [137, 'P', 'N', 'G'], format("%s not recognised as a PNG file.", filePath));

			input.seek(8);
			uint chunkSize = peek!uint(input.rawRead(new ubyte[4]));
			input.seek(0x18);
			
			assert(input.rawRead(new ubyte[1])[0] == 4, "Unsupported Bit Depth");
			assert(input.rawRead(new ubyte[1])[0] == 3, "Unsupported Colour Type");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Compression method");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Filter Type");
			assert(input.rawRead(new ubyte[1])[0] == 0, "Unsupported Interlacing");

			uint position = chunkSize + 20;
			ubyte[4] chunkName;
			ubyte[] colours;
			ubyte[] alphas;
			while (true)
			{
				input.seek(position);
				chunkSize = peek!uint(input.rawRead(new ubyte[4]));
				input.rawRead(chunkName);

				if (chunkName == ['P','L','T','E'])
				{
					colours = input.rawRead(new ubyte[chunkSize]);
				}
				else if (chunkName == ['t','R','N','S'])
				{
					alphas = input.rawRead(new ubyte[chunkSize]);
				}
				else if (chunkName == ['I','E','N','D'])
				{
					break;
				}

				position += chunkSize + 12;
			}
			input.close();
			for(int i = 0; i < colours.length; i += 3)
			{
				palette ~= Colour(
				                  ((colours[i]     / 8) << 11) |
				                  ((colours[i + 1] / 8) << 6) |
				                  ((colours[i + 2] / 8) << 1) |
				                  (alphas[i / 3] == 0 ? 0 : 1)
				                 );
			}
		}
		else
		{
			writeln("File not found: ", filePath);
		}
		return palette;
	}
}