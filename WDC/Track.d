module wdc.track;

import camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.drawable,
	   wdc.renderer,
	   wdc.trackCollisionSection,
	   wdc.trackMeshSection,
	   wdc.trackRenderer;

class Track : Drawable
{
	ubyte[] primaryBinary;
	TrackCollisionSection[] trackCollisionSections;
	TrackMeshSection[] trackMeshSections;

	private
	{
		TrackRenderer renderer;
	}

	this(ubyte[] data)
	{
		primaryBinary = data;
	}

	void addBinaryCollisionSection(ubyte[] newSectionBinary, int sectionInfo)
	{
		trackCollisionSections ~= new TrackCollisionSection(newSectionBinary, sectionInfo);
	}

	void addBinaryTrackSection(ubyte[] newSectionBinary, int sectionInfo)
	{
		trackMeshSections ~= new TrackMeshSection(newSectionBinary, sectionInfo);
	}

	void setupDrawing(OpenGL openglInstance)
	{
		renderer = new TrackRenderer(this, openglInstance);
	}

	void draw(Camera cam)
	{
		renderer.draw(cam);
	}
}