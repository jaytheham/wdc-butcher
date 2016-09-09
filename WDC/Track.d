module wdc.track;

import camera,
	   std.stdio,
	   gfm.math,
	   gfm.opengl,
	   wdc.tools,
	   wdc.drawable,
	   wdc.renderer,
	   wdc.trackRenderer;

class Track : Drawable
{
	private
	{
		struct Vertex
		{
			short Z;
			short X;
			short Y;
		}

		struct Polygon
		{
			long unknown_1; // Can probably get an idea of what these are from the car polygons
			ushort vertexIndexOne;
			ushort vertexIndexTwo;
			ushort vertexIndexThree;
			ushort vertexIndexFour;
			long unknown_2;
			long unknown_3;
		}

		struct Unknown
		{
			int unknown_1;
		}

		struct Colour
		{
			ubyte B;
			ubyte G;
			ubyte R;
			ubyte A;
		}

		struct ModelInfo
		{
			Vertex[] vertices;
			Polygon[] polygons;
			Unknown[] unknowns;
			Colour[] colours;
			int originX;
			int originY;
			int originZ;
		}

		struct TrackSection
		{
			ubyte[] binary;
			ModelInfo[] models;
		}

		// break this blob out into parts, like with trackSections
		ubyte[] mainBlob;

		TrackSection[] trackSections;

		TrackRenderer renderer;
	}

	this(ubyte[] data)
	{
		createFromBinary(data);
	}

	void addBinaryTrackSection(ubyte[] newSectionBinary, int sectionInfo)
	{
		trackSections ~= TrackSection(newSectionBinary);
		TrackSection newSection = trackSections[$ - 1];

		int modelInfo = sectionInfo + 8;
		int nextModelInfo = newSectionBinary.readInt(sectionInfo + 0x18);
		int numAdditionalModelInfo = newSectionBinary[sectionInfo + 0x1e];

		int modelPartsInfo;
		int vertices, polygons, unknowns, colours;
		int vertexCount, polygonCount, unknownCount, colourCount;

		while (numAdditionalModelInfo >= 0)
		{
			modelPartsInfo = newSectionBinary.readInt(modelInfo);

			vertexCount = newSectionBinary.readInt(modelPartsInfo + 4);
			polygonCount = newSectionBinary.readInt(modelPartsInfo + 12);
			unknownCount = newSectionBinary.readInt(modelPartsInfo + 20);
			colourCount = newSectionBinary.readInt(modelPartsInfo + 28);

			newSection.models ~= ModelInfo(new Vertex[vertexCount],
			                               new Polygon[polygonCount],
			                               new Unknown[unknownCount],
			                               new Colour[colourCount],
			                               newSectionBinary.readInt(modelInfo + 4),
			                               newSectionBinary.readInt(modelInfo + 8),
			                               newSectionBinary.readInt(modelInfo + 12)
			                              );

			vertices = newSectionBinary.readInt(modelPartsInfo);
			foreach (index; 0..vertexCount)
			{
				newSection.models[$ - 1].vertices[index] = Vertex(
				                                                  newSectionBinary.readShort(vertices + (index * 6)),
				                                                  newSectionBinary.readShort(vertices + 2 + (index * 6)),
				                                                  newSectionBinary.readShort(vertices + 4 + (index * 6))
				                                                 );
			}

			polygons = newSectionBinary.readInt(modelPartsInfo + 8);
			foreach(index; 0..polygonCount)
			{
				newSection.models[$ - 1].polygons[index] = Polygon(
				                                                   newSectionBinary.readLong(polygons + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 8 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 10 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 12 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 14 + (index * 32)),
				                                                   newSectionBinary.readLong(polygons + 16 + (index * 32)),
				                                                   newSectionBinary.readLong(polygons + 24 + (index * 32))
				                                                  );
			}

			unknowns = newSectionBinary.readInt(modelPartsInfo + 16);
			foreach(index; 0..unknownCount)
			{
				newSection.models[$ - 1].unknowns[index] = Unknown(newSectionBinary.readInt(unknowns + (index * 4)));
			}

			colours = newSectionBinary.readInt(modelPartsInfo + 24);
			foreach(index; 0..colourCount)
			{
				newSection.models[$ - 1].colours[index] = Colour(
				                                                 newSectionBinary[colours + (index * 4)],
				                                                 newSectionBinary[colours + 1 + (index * 4)],
				                                                 newSectionBinary[colours + 2 + (index * 4)],
				                                                 newSectionBinary[colours + 3 + (index * 4)]
				                                                );
			}
			modelInfo = nextModelInfo;
			nextModelInfo += 0x10;
			
			numAdditionalModelInfo -= 1;
		}
	}

	void enableDrawing(OpenGL openglInstance, GLProgram programInstance)
	{
		// TODO, refactor car and drawable so this can be removed, its on renderer
	}

	void draw(Camera cam)
	{
		// TODO, refactor car and drawable so this can be removed, its on renderer
	}

	Renderer getRenderer(OpenGL openglInstance, GLProgram programInstance)
	{
		if (renderer is null)
		{
			renderer = new TrackRenderer(this, openglInstance, programInstance);
		}
		return renderer;
	}

private:

	void createFromBinary(ubyte[] data)
	{
		mainBlob = data;
	}
	
}