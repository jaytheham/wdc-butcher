module wdc.track;

class Track
{
	private
	{
		ubyte[] dataBlob;
	}

	this(ubyte[] data)
	{
		createFromBinary(data);
	}

private:

	createFromBinary(ubyte[] data)
	{
		dataBlob = data;
	}
	
}