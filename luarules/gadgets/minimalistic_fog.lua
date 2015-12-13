--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function gadget:GetInfo()
  return {
    name      = "DualFog",
    version   = 3,
    desc      = "Fog Drawing Gadget",
    author    = "trepan, user, aegis, jK, beherith",
    date      = "2008-2011",
    license   = "GNU GPL, v2 or later",
    layer     = 1,
    enabled   = true
  }
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

enabled = true

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Config

local fogHeight    = 10000
local fogColor  = { 0.25, 0.4, 0.3 }
local fogAtten  = 0.007 --0.08
local fr,fg,fb     = unpack(fogColor)


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Automatically generated local definitions

local GL_MODELVIEW           = GL.MODELVIEW
local GL_NEAREST             = GL.NEAREST
local GL_ONE                 = GL.ONE
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_PROJECTION          = GL.PROJECTION
local GL_QUADS               = GL.QUADS
local GL_SRC_ALPHA           = GL.SRC_ALPHA
local glBeginEnd             = gl.BeginEnd
local glBlending             = gl.Blending
local glCallList             = gl.CallList
local glColor                = gl.Color
local glColorMask            = gl.ColorMask
local glCopyToTexture        = gl.CopyToTexture
local glCreateList           = gl.CreateList
local glCreateShader         = gl.CreateShader
local glCreateTexture        = gl.CreateTexture
local glDeleteShader         = gl.DeleteShader
local glDeleteTexture        = gl.DeleteTexture
local glDepthMask            = gl.DepthMask
local glDepthTest            = gl.DepthTest
local glGetMatrixData        = gl.GetMatrixData
local glGetShaderLog         = gl.GetShaderLog
local glGetUniformLocation   = gl.GetUniformLocation
local glGetViewSizes         = gl.GetViewSizes
local glLoadIdentity         = gl.LoadIdentity
local glLoadMatrix           = gl.LoadMatrix
local glMatrixMode           = gl.MatrixMode
local glMultiTexCoord        = gl.MultiTexCoord
local glPopMatrix            = gl.PopMatrix
local glPushMatrix           = gl.PushMatrix
local glResetMatrices        = gl.ResetMatrices
local glTexCoord             = gl.TexCoord
local glTexture              = gl.Texture
local glRect                 = gl.Rect
local glUniform              = gl.Uniform
local glUniformMatrix        = gl.UniformMatrix
local glUseShader            = gl.UseShader
local glVertex               = gl.Vertex
local glTranslate            = gl.Translate
local spEcho                 = Spring.Echo
local spGetCameraPosition    = Spring.GetCameraPosition
local spGetCameraVectors     = Spring.GetCameraVectors
local spGetDrawFrame         = Spring.GetDrawFrame

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Extra GL constants
--

local GL_DEPTH_BITS = 0x0D56

local GL_DEPTH_COMPONENT   = 0x1902
local GL_DEPTH_COMPONENT16 = 0x81A5
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_DEPTH_COMPONENT32 = 0x81A7


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local debugGfx  = false --or true

local GLSLRenderer = true




--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local gnd_min, gnd_max = Spring.GetGroundExtremes()
if (gnd_min < 0) then gnd_min = 0 end
if (gnd_max < 0) then gnd_max = 0 end
local vsx, vsy
local mx = Game.mapSizeX
local mz = Game.mapSizeZ
local fog

local depthShader
local depthTexture

local uniformEyePos
local uniformViewPrjInv



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- fog rendering



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:ViewResize()
	vsx, vsy = gl.GetViewSizes()
	if (Spring.GetMiniMapDualScreen()=='left') then
		vsx=vsx/2;
	end
	if (Spring.GetMiniMapDualScreen()=='right') then
		vsx=vsx/2
	end

	if (depthTexture) then
		glDeleteTexture(depthTexture)
	end

	depthTexture = glCreateTexture(vsx, vsy, {
		format = GL_DEPTH_COMPONENT24,
		min_filter = GL_NEAREST,
		mag_filter = GL_NEAREST,
	})

	if (depthTexture == nil) then
		spEcho("Removing fog gadget, bad depth texture")
		gadgetHandler:Removegadget()
	end
end

gadget:ViewResize()


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local vertSrc = [[

  void main(void)
  {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position    = gl_Vertex;
  }
]]

local fragSrc = ([[
  const float fogAtten  = %f;
  const float fogHeight = %f;
  const vec3 fogColor   = vec3(%f, %f, %f);

  uniform sampler2D tex0;
  uniform vec3 eyePos;
  uniform mat4 viewProjectionInv;

  void main(void)
  {
    float z = texture2D(tex0, gl_TexCoord[0].st).x;

    vec4 ppos;
    ppos.xyz = vec3(gl_TexCoord[0].st, z) * 2. - 1.;
    ppos.a   = 1.;

    vec4 worldPos4 = viewProjectionInv * ppos;

    vec3 worldPos  = worldPos4.xyz / worldPos4.w;
    vec3 toPoint   = worldPos - eyePos;

#ifdef DEBUG_GFX // world position debugging
    const float k  = 100.0;
    vec3 debugColor =worldPos4.xyz;
    gl_FragColor = vec4(fract(worldPos.x/50),fract(worldPos.y/50),fract(worldPos.z/50), 1.0);
    return; // BAIL
#endif
    float bleh=min(3000, 1350 + 0.4 * (max(0,abs(worldPos.x-5120)-3072) + max(0,abs(worldPos.z-5120)-3072)) );
    float h0 = clamp(worldPos.y, 0.0, bleh);
    float h1 = clamp(eyePos.y,   0.0, bleh); // FIXME: uniform ...

    float len = length(toPoint);
    float dist = len * abs((h1 - h0) / toPoint.y); // div-by-zero prob?
    float atten = clamp(1.0 - exp(-dist * fogAtten), 0.0, 1.0);

    gl_FragColor = vec4(fogColor, atten);
  }
]]):format(fogAtten, fogHeight, fogColor[1], fogColor[2], fogColor[3])



if (debugGfx) then
  fragSrc = '#define DEBUG_GFX\n' .. fragSrc
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:Initialize()
	if (enabled) then
		if ((not forceNonGLSL) and Spring.GetMiniMapDualScreen()~='left') then --FIXME dualscreen
			if (not glCreateShader) then
				spEcho("Shaders not found, reverting to non-GLSL gadget")
				GLSLRenderer = false
			else
				depthShader = glCreateShader({
					vertex = vertSrc,
					fragment = fragSrc,
					uniformInt = {
						tex0 = 0,
					},
				})

				if (not depthShader) then
					spEcho(glGetShaderLog())
					spEcho("Bad shader, reverting to non-GLSL gadget.")
					GLSLRenderer = false
				else
					uniformEyePos       = glGetUniformLocation(depthShader, 'eyePos')
					uniformViewPrjInv   = glGetUniformLocation(depthShader, 'viewProjectionInv')
				end
			end
		else
			GLSLRenderer = false
		end
	else
		gadgetHandler:RemoveGadget()
	end
end


function gadget:Shutdown()
  if (GLSLRenderer) then
    glDeleteTexture(depthTexture)
    if (glDeleteShader) then
      glDeleteShader(depthShader)
    end
  end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local dl

local function DrawFogNew()
	--//FIXME handle dualscreen correctly!
	-- copy the depth buffer

	glCopyToTexture(depthTexture, 0, 0, 0, 0, vsx, vsy ) --FIXME scale down?
	
	-- setup the shader and its uniform values
	glUseShader(depthShader)

	-- set uniforms
	local cpx, cpy, cpz = spGetCameraPosition()
	glUniform(uniformEyePos, cpx, cpy, cpz)

	glUniformMatrix(uniformViewPrjInv,  "viewprojectioninverse")

	if (not dl) then
		dl = gl.CreateList(function()
			-- render a full screen quad
			glTexture(0, depthTexture)
			glTexture(0, false)
			gl.TexRect(-1, -1, 1, 1, 0, 0, 1, 1)

			--// finished
			glUseShader(0)
		end)
	end

	glCallList(dl)
end

function Drawquad(x1,z1, x2,z2, y )
		local s=1
		gl.Normal(0,1,0)
		gl.TexCoord(-s,-s)
		gl.Vertex(x1,y,z1)
		
		gl.Normal(0,1,0)
		gl.TexCoord(-s,s) 
		gl.Vertex(x1,y,z2)
		
		gl.Normal(0,1,0)
		gl.TexCoord(s,s)
		gl.Vertex(x2,y,z2)
		
		gl.Normal(0,1,0)
		gl.TexCoord(s,-s)
		gl.Vertex(x2,y,z1)
		
		
		gl.Normal(0,1,0)
		gl.TexCoord(-s,-s)
		gl.Vertex(x1,y,z1)
		
		gl.Normal(0,1,0)
		gl.TexCoord(-s,s) 
		gl.Vertex(x2,y,z1)
		
		gl.Normal(0,1,0)
		gl.TexCoord(s,s)
		gl.Vertex(x2,y,z2)
		
		gl.Normal(0,1,0)
		gl.TexCoord(s,-s)
		gl.Vertex(x1,y,z2)
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:DrawWorld()
	if (GLSLRenderer) then
		--if (debugGfx) then glBlending(GL_SRC_ALPHA, GL_ONE) end
		DrawFogNew()
		--if (debugGfx) then glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) end
	else
		Spring.Echo('failed to use GLSL shader')
	end
end



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
