module wdc.trackCollisionSection;

import std.stdio,
	   gfm.math,
	   wdc.tools;

class TrackCollisionSection
{

	struct Polygon
	{
		ushort vertexIndexOne;
		ushort vertexIndexTwo;
		ushort vertexIndexThree;
		ushort unknown1;
		// this looks like (most of the time) it is an
		// index into the values of unknownAs (sectionInfo + 0x10)
		ubyte unknown2;
		// if unknown1 is an index then this is 0x80 (or vice versa)
		ubyte groundType;
		// Varies from track to track
		// for black forest A 0=dirt, 1=grass, 2=corner bumpers, 3=road
		// for rome A 0=dirt 1=gravel 2=road 3=cobblestones 4=? 5=bumpers
	}

	struct Vertex
	{
		float z;
		float x;
		float y;
		vec4ub lightColour; // Alpha is always 0x00, the game ignores it

		// Are these indices into UnknownB?
		short unknown1;
		// These increase in value the further around the track this point is in clockwise direction
		// They reset to 0 a lot less than unknown2, usually (always?) at points where variations diverge
		// The sections where they equal 0xffff are the sections where track variations diverge
		// but are part of both variations
		short unknown2;
		// These increase in value the further around the track this point is in anti-clockwise direction
		// Regularly restarting from 0
		// Used to tell if you're driving the wrong way? Or your placing?
	}

	struct UnknownA
	{
		// Setting all of these to 0xffff for a polygon will prevent you from drving onto it
		// The camera will try avoid going through it too
		short unknown1;
		short unknown2;
		short unknown3;
		short unknown4;
		short unknown5;
		short unknown6;
	}

	struct UnknownB
	{
		int unknown1;
		// These are always 0. The game stores values here after loading the track.
	}

	ubyte[] binary;
	Polygon[] polygons;
	Vertex[] vertices;
	UnknownA[] unknownAs;
	UnknownB[] unknownBs;

	this(ubyte[] newSectionBinary, int sectionInfo)
	{
		binary = newSectionBinary;
		
		int polygonData = binary.readInt(sectionInfo);
		int polygonCount = binary.readInt(sectionInfo + 4);
		foreach(index; 0..polygonCount)
		{
			polygons ~= Polygon(
			                    binary.readUshort(polygonData + (index * 10)),
			                    binary.readUshort(polygonData + 2 + (index * 10)),
			                    binary.readUshort(polygonData + 4 + (index * 10)),
			                    binary.readUshort(polygonData + 6 + (index * 10)),
			                    binary[polygonData + 8 + (index * 10)],
			                    binary[polygonData + 9 + (index * 10)]
			                   );
		}

		int vertexData = binary.readInt(sectionInfo + 8);
		int vertexCount = binary.readInt(sectionInfo + 12);
		foreach(index; 0..vertexCount)
		{
			vertices ~= Vertex(
			                   binary.readFloat(vertexData + (index * 20)),
			                   binary.readFloat(vertexData + 4 + (index * 20)),
			                   binary.readFloat(vertexData + 8 + (index * 20)),
			                   vec4ub(
			                   	      binary[vertexData + 12 + (index * 20)],
			                   	      binary[vertexData + 13 + (index * 20)],
			                   	      binary[vertexData + 14 + (index * 20)],
			                   	      cast(ubyte)0xff//<<--Hack so can see colours
			                   	      //binary[vertexData + 15 + (index * 20)]
			                   	     ),
			                   binary.readShort(vertexData + 16 + (index * 20)),
			                   binary.readShort(vertexData + 18 + (index * 20))
			                  );
			assert(binary[vertexData + 15 + (index * 20)] == 0x00, "TrackCollision colour has Alpha");
		}

		int unknownAData = binary.readInt(sectionInfo + 16);
		int unknownACount = binary.readInt(sectionInfo + 20);
		foreach(index; 0..unknownACount)
		{
			unknownAs ~= UnknownA(
			                   binary.readShort(unknownAData + (index * 12)),
			                   binary.readShort(unknownAData + 2 + (index * 12)),
			                   binary.readShort(unknownAData + 4 + (index * 12)),
			                   binary.readShort(unknownAData + 6 + (index * 12)),
			                   binary.readShort(unknownAData + 8 + (index * 12)),
			                   binary.readShort(unknownAData + 10 + (index * 12))
			                  );
		}

		int unknownBData = binary.readInt(sectionInfo + 24);
		int unknownBCount = binary.readInt(sectionInfo + 28);
		foreach(index; 0..unknownBCount)
		{
			unknownBs ~= UnknownB(binary.readInt(unknownBData + (index * 4)));
		}
	}
}