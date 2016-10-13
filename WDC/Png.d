module wdc.png;

import std.zlib,
       wdc.car;

static class Png
{
	static uint[256] crcTable;

	public static ubyte[] wdcTextureToPng(Car.Colour[] palette, ubyte[] texture, uint width, uint height)
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
}