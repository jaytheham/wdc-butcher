module wdc.track;

import camera,
	   gfm.opengl,
	   wdc.drawable;

class Track : Drawable
{
	private
	{
		ubyte[] dataBlob;
	}

	this(ubyte[] data)
	{
		createFromBinary(data);
	}

	void enableDrawing(OpenGL openglInstance, GLProgram programInstance)
	{

	}

	void draw(Camera cam)
	{

	}

private:

	void createFromBinary(ubyte[] data)
	{
		dataBlob = data;
	}
	
}