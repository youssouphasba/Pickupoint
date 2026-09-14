import React from 'react';
import {
  AbsoluteFill,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const palette = {
  bg: '#09040f',
  bg2: '#16071f',
  violet: '#8b5cf6',
  violetSoft: '#b794ff',
  cyan: '#8ce7ff',
  white: '#f8f8fb',
  text: '#f7f2ff',
  textDark: '#141018',
  line: 'rgba(255,255,255,0.08)',
};

const baseScreenStyle: React.CSSProperties = {
  position: 'absolute',
  width: 660,
  borderRadius: 44,
  boxShadow:
    '0 32px 120px rgba(0,0,0,0.55), 0 0 0 2px rgba(188,148,255,0.22), 0 0 140px rgba(150,92,246,0.28)',
};

const primaryFont =
  '"Aptos","Bahnschrift","Trebuchet MS","Segoe UI",sans-serif';

type FocusCue = {
  x: number;
  y: number;
  w: number;
  h: number;
  start: number;
  end: number;
  scale?: number;
  kind?: 'zoom' | 'tap' | 'tap-zoom';
};

type ScreenSceneProps = {
  image: string;
  kicker?: string;
  title: string[];
  subtitle?: string[];
  cues: FocusCue[];
  titleTop?: number;
  titleSize?: number;
  subtitleTop?: number;
  screenWidth?: number;
  screenX?: number;
  screenY?: number;
  durationInFrames: number;
  entrySide?: 'left' | 'right';
  dark?: boolean;
  accent?: 'violet' | 'cyan';
};

const fitHeight = (width: number, sourceWidth: number, sourceHeight: number) =>
  (width / sourceWidth) * sourceHeight;

const sourceScreen = {
  width: 945,
  height: 2048,
};

const useEntrance = (delay = 0, damping = 12) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({
    fps,
    frame: frame - delay,
    config: {
      damping,
      mass: 0.9,
      stiffness: 110,
    },
  });
};

const DarkBackdrop: React.FC<{soft?: boolean}> = ({soft = false}) => {
  const frame = useCurrentFrame();
  const drift = Math.sin(frame / 34) * 24;
  const opacity = soft ? 0.5 : 0.9;

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 50% ${28 + drift / 20}%, rgba(122,72,246,${0.34 * opacity}) 0%, rgba(67,18,94,${0.24 * opacity}) 28%, rgba(9,4,15,1) 70%)`,
      }}
    >
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0) 32%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          backgroundImage:
            'linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px)',
          backgroundSize: '120px 120px',
          opacity: 0.22,
          transform: `translate3d(0, ${drift}px, 0) scale(1.05)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: -160,
          top: 1180,
          width: 520,
          height: 520,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(120,72,246,0.28), rgba(120,72,246,0))',
          filter: 'blur(18px)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          right: -220,
          top: 240,
          width: 640,
          height: 640,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(150,92,246,0.2), rgba(150,92,246,0))',
          filter: 'blur(28px)',
        }}
      />
    </AbsoluteFill>
  );
};

const LightBackdrop: React.FC = () => {
  const frame = useCurrentFrame();
  const rotation = frame * 0.08;

  return (
    <AbsoluteFill
      style={{
        background:
          'radial-gradient(circle at 20% 85%, rgba(160,112,255,0.18), transparent 28%), radial-gradient(circle at 80% 18%, rgba(121,237,255,0.16), transparent 24%), #faf8ff',
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 80,
          borderRadius: 80,
          border: '2px solid rgba(128,92,246,0.08)',
          transform: `rotate(${rotation}deg)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 180,
          borderRadius: 100,
          border: '2px solid rgba(128,92,246,0.06)',
          transform: `rotate(${-rotation * 1.2}deg)`,
        }}
      />
    </AbsoluteFill>
  );
};

const WordCascade: React.FC<{
  lines: string[];
  top?: number;
  color?: string;
  align?: 'center' | 'left';
  size?: number;
  accentIndexes?: number[];
}> = ({
  lines,
  top = 180,
  color = palette.text,
  align = 'center',
  size = 74,
  accentIndexes = [],
}) => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        position: 'absolute',
        top,
        left: align === 'center' ? 120 : 92,
        right: 120,
        fontFamily: primaryFont,
        color,
        fontWeight: 700,
        fontSize: size,
        lineHeight: 1.02,
        letterSpacing: '-0.02em',
        textAlign: align,
      }}
    >
      {lines.map((line, lineIndex) => {
        const words = line.split(' ');
        return (
          <div key={line + lineIndex} style={{marginBottom: 16}}>
            {words.map((word, wordIndex) => {
              const index = words
                .slice(0, wordIndex)
                .reduce((acc, item) => acc + item.length, 0);
              const appear = spring({
                fps: 30,
                frame: frame - lineIndex * 8 - wordIndex * 3,
                config: {
                  damping: 14,
                  stiffness: 140,
                  mass: 0.8,
                },
              });
              const offsetY = interpolate(appear, [0, 1], [34, 0]);
              const opacity = interpolate(appear, [0, 1], [0, 1]);
              const isAccent = accentIndexes.includes(index + wordIndex);

              return (
                <span
                  key={word + wordIndex}
                  style={{
                    display: 'inline-block',
                    marginRight: 18,
                    transform: `translateY(${offsetY}px)`,
                    opacity,
                    color: isAccent ? palette.violetSoft : color,
                    textShadow: isAccent
                      ? '0 0 26px rgba(166,120,255,0.45)'
                      : 'none',
                  }}
                >
                  {word}
                </span>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};

const Subcopy: React.FC<{
  lines: string[];
  top: number;
  color?: string;
}> = ({lines, top, color = 'rgba(248,242,255,0.74)'}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [10, 24], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <div
      style={{
        position: 'absolute',
        top,
        left: 110,
        right: 110,
        fontFamily: primaryFont,
        color,
        fontSize: 34,
        lineHeight: 1.28,
        textAlign: 'center',
        opacity,
      }}
    >
      {lines.map((line) => (
        <div key={line}>{line}</div>
      ))}
    </div>
  );
};

const ScreenCard: React.FC<{
  image: string;
  width: number;
  x: number;
  y: number;
  cues: FocusCue[];
  accent?: 'violet' | 'cyan';
  durationInFrames: number;
  entrySide?: 'left' | 'right';
}> = ({image, width, x, y, cues, accent = 'violet', durationInFrames, entrySide = 'right'}) => {
  const frame = useCurrentFrame();
  const glowColor =
    accent === 'cyan' ? 'rgba(140,231,255,0.95)' : 'rgba(185,122,255,0.95)';
  const screenHeight = fitHeight(width, sourceScreen.width, sourceScreen.height);
  const enter = spring({
    fps: 30,
    frame,
    config: {damping: 16, stiffness: 110, mass: 0.9},
  });
  const exit = interpolate(
    frame,
    [durationInFrames - 18, durationInFrames],
    [0, 1],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );
  const idleDriftY = Math.sin(frame / 18) * 8;
  const idleDriftX = Math.cos(frame / 28) * 6;

  const activeCue = cues.find((cue) => frame >= cue.start && frame <= cue.end) ?? null;
  const cueProgress = activeCue
    ? spring({
        fps: 30,
        frame: frame - activeCue.start,
        durationInFrames: Math.max(8, activeCue.end - activeCue.start),
        config: {damping: 17, stiffness: 120, mass: 0.9},
      })
    : 0;

  let contentTransform = 'translate3d(0,0,0) scale(1)';
  let cueCenterX = 0;
  let cueCenterY = 0;

  if (activeCue) {
    const left = activeCue.x * width;
    const top = activeCue.y * screenHeight;
    const boxWidth = activeCue.w * width;
    const boxHeight = activeCue.h * screenHeight;
    cueCenterX = left + boxWidth / 2;
    cueCenterY = top + boxHeight / 2;
    const cueScale = interpolate(
      cueProgress,
      [0, 1],
      [1, activeCue.scale ?? (activeCue.kind === 'zoom' ? 1.28 : 1.18)],
    );
    const tilt = interpolate(cueProgress, [0, 1], [0, activeCue.kind === 'tap' ? -0.4 : -0.8]);
    contentTransform = `scale(${cueScale}) rotate(${tilt}deg)`;
  }

  return (
    <div
      style={{
        ...baseScreenStyle,
        width,
        left: x,
        top: y,
        transform: `translateY(${interpolate(enter, [0, 1], [90, 0]) + idleDriftY + interpolate(exit, [0, 1], [0, -60])}px) translateX(${interpolate(
          enter,
          [0, 1],
          [entrySide === 'right' ? 180 : -180, 0],
        ) + idleDriftX + interpolate(exit, [0, 1], [0, entrySide === 'right' ? -120 : 120])}px) scale(${interpolate(
          enter,
          [0, 1],
          [0.86, 1],
        ) * interpolate(exit, [0, 1], [1, 0.92])}) rotate(${interpolate(
          enter,
          [0, 1],
          [entrySide === 'right' ? 8 : -8, 0],
        ) + interpolate(exit, [0, 1], [0, entrySide === 'right' ? -4 : 4])}deg)`,
        opacity: interpolate(enter, [0, 1], [0, 1]) * interpolate(exit, [0, 1], [1, 0]),
        filter: `blur(${interpolate(enter, [0, 1], [18, 0]) + interpolate(exit, [0, 1], [0, 8])}px)`,
      }}
    >
      <div
        style={{
          position: 'relative',
          overflow: 'hidden',
          borderRadius: 44,
          width: '100%',
          height: screenHeight,
        }}
      >
        <div
          style={{
            position: 'absolute',
            inset: 0,
            transformOrigin: activeCue ? `${cueCenterX}px ${cueCenterY}px` : '50% 50%',
            transform: contentTransform,
          }}
        >
          <Img
            src={staticFile(image)}
            style={{
              width: '100%',
              height: screenHeight,
              objectFit: 'cover',
              borderRadius: 44,
              display: 'block',
            }}
          />
        </div>
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background:
              activeCue && activeCue.kind !== 'tap'
                ? `radial-gradient(circle at ${cueCenterX}px ${cueCenterY}px, rgba(255,255,255,0) 0 150px, rgba(7,4,16,0.08) 180px, rgba(7,4,16,0.28) 100%)`
                : 'transparent',
            pointerEvents: 'none',
          }}
        />
        {activeCue ? (
          <>
            <div
              style={{
                position: 'absolute',
                left: cueCenterX - 18,
                top: cueCenterY - 18,
                width: 36,
                height: 36,
                borderRadius: '50%',
                background: 'rgba(255,255,255,0.96)',
                boxShadow: `0 0 24px ${glowColor}, 0 0 54px ${glowColor.replace('0.95', '0.45')}`,
                opacity: activeCue.kind === 'zoom' ? interpolate(cueProgress, [0, 1], [0, 0.9]) : 1,
                transform: `scale(${interpolate(cueProgress, [0, 1], [0.4, 1])})`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: cueCenterX - 18,
                top: cueCenterY - 18,
                width: 36,
                height: 36,
                borderRadius: '50%',
                border: `3px solid ${glowColor}`,
                opacity: interpolate(cueProgress, [0, 0.85, 1], [0, 0.9, 0]),
                transform: `scale(${interpolate(cueProgress, [0, 1], [0.4, 3.2])})`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: cueCenterX - 64,
                top: cueCenterY - 64,
                width: 128,
                height: 128,
                borderRadius: '50%',
                border: `1px solid ${glowColor.replace('0.95', '0.42')}`,
                opacity: interpolate(cueProgress, [0, 0.3, 1], [0, 0.65, 0]),
                transform: `scale(${interpolate(cueProgress, [0, 1], [0.5, 1.8])})`,
              }}
            />
          </>
        ) : null}
      </div>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: 44,
          boxShadow: `inset 0 0 0 2px rgba(255,255,255,0.1), 0 0 48px ${glowColor.replace(
            '0.95',
            '0.18',
          )}`,
        }}
      />
    </div>
  );
};

const AudienceScene: React.FC = () => {
  const frame = useCurrentFrame();
  const items = ['Particuliers', 'Commerçants', 'Restaurants', 'GP'];

  return (
    <AbsoluteFill>
      <DarkBackdrop />
      <WordCascade lines={['Pensé pour vous.']} top={172} size={88} />
      {items.map((item, index) => {
        const progress = spring({
          fps: 30,
          frame: frame - 22 - index * 8,
          config: {
            damping: 15,
            stiffness: 130,
            mass: 0.9,
          },
        });
        const fromLeft = index % 2 === 0;

        return (
          <div
            key={item}
            style={{
              position: 'absolute',
              left: fromLeft ? 96 : 396,
              top: 470 + index * 190,
              width: 588,
              padding: '34px 42px',
              borderRadius: 34,
              background: 'rgba(255,255,255,0.08)',
              border: '1px solid rgba(255,255,255,0.14)',
              color: palette.text,
              fontFamily: primaryFont,
              fontSize: 42,
              fontWeight: 700,
              boxShadow:
                '0 24px 80px rgba(0,0,0,0.32), inset 0 0 40px rgba(255,255,255,0.05)',
              transform: `translateX(${interpolate(
                progress,
                [0, 1],
                [fromLeft ? -180 : 180, 0],
              )}px) translateY(${interpolate(progress, [0, 1], [18, 0])}px)`,
              opacity: progress,
            }}
          >
            {item}
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

const IntroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const logoIn = useEntrance(0, 16);
  const ripple = interpolate(frame, [10, 55], [0.7, 1.4], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const rippleOpacity = interpolate(frame, [10, 55], [0.32, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill>
      <DarkBackdrop />
      <div
        style={{
          position: 'absolute',
          left: 300,
          top: 390,
          width: 480,
          height: 480,
          borderRadius: '50%',
          border: '2px solid rgba(190,142,255,0.4)',
          transform: `scale(${ripple})`,
          opacity: rippleOpacity,
          boxShadow: '0 0 120px rgba(170,110,255,0.35)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 270,
          top: 350,
          width: 540,
          padding: 46,
          borderRadius: 48,
          background: 'rgba(255,255,255,0.06)',
          border: '1px solid rgba(255,255,255,0.12)',
          boxShadow:
            '0 28px 120px rgba(0,0,0,0.38), inset 0 0 60px rgba(255,255,255,0.04), 0 0 90px rgba(144,86,246,0.28)',
          backdropFilter: 'blur(18px)',
          transform: `scale(${interpolate(logoIn, [0, 1], [0.86, 1])}) translateY(${interpolate(
            logoIn,
            [0, 1],
            [50, 0],
          )}px)`,
          opacity: logoIn,
        }}
      >
        <Img
          src={staticFile('assets/logo.png')}
          style={{
            width: 100,
            height: 100,
            objectFit: 'contain',
            margin: '0 auto 22px',
            display: 'block',
          }}
        />
        <div
          style={{
            textAlign: 'center',
            fontFamily: primaryFont,
            color: palette.text,
            fontSize: 86,
            lineHeight: 0.98,
            fontWeight: 800,
            letterSpacing: '-0.03em',
          }}
        >
          DENKMA
        </div>
      </div>
      <WordCascade lines={['Denkma, livrez facilement.']} top={1000} size={72} />
    </AbsoluteFill>
  );
};

const ScreenScene: React.FC<ScreenSceneProps> = ({
  image,
  kicker,
  title,
  subtitle,
  cues,
  titleTop,
  titleSize,
  subtitleTop,
  screenWidth = 670,
  screenX = 205,
  screenY = 540,
  durationInFrames,
  entrySide = 'right',
  dark = true,
  accent = 'violet',
}) => {
  const frame = useCurrentFrame();
  const textExit = interpolate(
    frame,
    [durationInFrames - 16, durationInFrames],
    [1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );
  return (
    <AbsoluteFill>
      {dark ? <DarkBackdrop soft /> : <LightBackdrop />}
      {kicker ? (
        <div
          style={{
            position: 'absolute',
            top: 118,
            left: 110,
            padding: '12px 24px',
            borderRadius: 999,
            background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(20,16,24,0.08)',
            border: dark
              ? '1px solid rgba(255,255,255,0.14)'
              : '1px solid rgba(20,16,24,0.08)',
            fontFamily: primaryFont,
            color: dark ? palette.violetSoft : '#5f34bf',
            fontSize: 24,
            fontWeight: 700,
            letterSpacing: '0.08em',
            textTransform: 'uppercase',
            opacity: textExit,
          }}
        >
          {kicker}
        </div>
      ) : null}
      <div style={{opacity: textExit}}>
        <WordCascade
          lines={title}
          top={titleTop ?? (dark ? 178 : 160)}
          color={dark ? palette.text : palette.textDark}
          size={titleSize ?? (dark ? 72 : 76)}
        />
        {subtitle ? (
          <Subcopy
            lines={subtitle}
            top={subtitleTop ?? (dark ? 360 : 340)}
            color={dark ? 'rgba(248,242,255,0.74)' : 'rgba(20,16,24,0.64)'}
          />
        ) : null}
      </div>
      <ScreenCard
        image={image}
        width={screenWidth}
        x={screenX}
        y={screenY}
        cues={cues}
        accent={accent}
        durationInFrames={durationInFrames}
        entrySide={entrySide}
      />
    </AbsoluteFill>
  );
};

const OutroScene: React.FC = () => {
  const inMotion = useEntrance(0, 16);

  return (
    <AbsoluteFill>
      <DarkBackdrop />
      <div
        style={{
          position: 'absolute',
          left: 360,
          top: 250,
          width: 360,
          height: 360,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(171,118,255,0.36), rgba(171,118,255,0))',
          filter: 'blur(10px)',
          opacity: 0.9,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 390,
          top: 290,
          width: 300,
          padding: 28,
          borderRadius: 38,
          background: 'rgba(255,255,255,0.07)',
          border: '1px solid rgba(255,255,255,0.12)',
          boxShadow: '0 0 90px rgba(149,89,246,0.22)',
          transform: `scale(${interpolate(inMotion, [0, 1], [0.88, 1])})`,
        }}
      >
        <Img
          src={staticFile('assets/logo.png')}
          style={{width: 120, height: 120, display: 'block', margin: '0 auto'}}
        />
      </div>
      <WordCascade
        lines={[
          "Téléchargez l'application maintenant",
          'et profitez de nos offres.',
        ]}
        top={760}
        size={62}
      />
      <div
        style={{
          position: 'absolute',
          bottom: 250,
          left: 0,
          right: 0,
          textAlign: 'center',
          fontFamily: primaryFont,
          fontSize: 76,
          fontWeight: 800,
          letterSpacing: '-0.03em',
          color: palette.text,
        }}
      >
        Denkma.com
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 224,
          left: 260,
          right: 260,
          height: 6,
          borderRadius: 999,
          background:
            'linear-gradient(90deg, rgba(112,68,240,0.2), rgba(185,132,255,1), rgba(112,68,240,0.2))',
          boxShadow: '0 0 34px rgba(171,118,255,0.42)',
        }}
      />
    </AbsoluteFill>
  );
};

export const DenkmaPromo: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: palette.bg}}>
      <Sequence from={0} durationInFrames={120}>
        <IntroScene />
      </Sequence>
      <Sequence from={120} durationInFrames={150}>
        <AudienceScene />
      </Sequence>
      <Sequence from={270} durationInFrames={180}>
        <ScreenScene
          kicker="Simplicité"
          title={[
            'Pas besoin de connaître votre adresse',
            'ni celle de votre destinataire',
          ]}
          cues={[
            {x: 0.089, y: 0.282, w: 0.749, h: 0.059, start: 36, end: 92, kind: 'zoom', scale: 1.18},
            {x: 0.548, y: 0.815, w: 0.364, h: 0.067, start: 98, end: 152, kind: 'tap-zoom', scale: 1.24},
          ]}
          durationInFrames={180}
          entrySide="right"
          image="assets/screen-home.jpeg"
        />
      </Sequence>
      <Sequence from={450} durationInFrames={180}>
        <ScreenScene
          kicker="Choix"
          title={['Choisissez votre mode de livraison.']}
          cues={[
            {x: 0.065, y: 0.182, w: 0.872, h: 0.127, start: 28, end: 78, kind: 'tap-zoom', scale: 1.16},
            {x: 0.064, y: 0.667, w: 0.872, h: 0.111, start: 80, end: 128, kind: 'tap-zoom', scale: 1.17},
            {x: 0.065, y: 0.79, w: 0.872, h: 0.071, start: 128, end: 164, kind: 'tap', scale: 1.14},
          ]}
          durationInFrames={180}
          entrySide="left"
          image="assets/screen-delivery-mode.jpeg"
        />
      </Sequence>
      <Sequence from={630} durationInFrames={210}>
        <ScreenScene
          kicker="Destinataire"
          title={[
            'Vous avez besoin que du numéro',
            'de téléphone du destinataire',
          ]}
          subtitle={["L'adresse est facultative, pas obligatoire."]}
          titleTop={150}
          titleSize={62}
          subtitleTop={420}
          cues={[
            {x: 0.064, y: 0.194, w: 0.872, h: 0.056, start: 42, end: 92, kind: 'zoom', scale: 1.14},
            {x: 0.064, y: 0.531, w: 0.874, h: 0.071, start: 108, end: 176, kind: 'tap-zoom', scale: 1.22},
          ]}
          durationInFrames={210}
          entrySide="right"
          image="assets/screen-recipient.jpeg"
        />
      </Sequence>
      <Sequence from={840} durationInFrames={180}>
        <ScreenScene
          kicker="Colis"
          title={['Renseignez les infos du colis']}
          subtitle={["Puis c'est bon, le destinataire sera notifié"]}
          cues={[
            {x: 0.064, y: 0.365, w: 0.411, h: 0.138, start: 34, end: 86, kind: 'zoom', scale: 1.18},
            {x: 0.519, y: 0.365, w: 0.417, h: 0.138, start: 82, end: 122, kind: 'zoom', scale: 1.18},
            {x: 0.383, y: 0.795, w: 0.553, h: 0.071, start: 122, end: 160, kind: 'tap', scale: 1.14},
          ]}
          durationInFrames={180}
          entrySide="left"
          image="assets/screen-parcel-info.jpeg"
        />
      </Sequence>
      <Sequence from={1020} durationInFrames={180}>
        <ScreenScene
          kicker="Instantané"
          title={['Votre destinataire est prévenu', 'instantanément']}
          cues={[
            {x: 0.035, y: 0.283, w: 0.931, h: 0.072, start: 34, end: 90, kind: 'zoom', scale: 1.14},
            {x: 0.035, y: 0.383, w: 0.931, h: 0.096, start: 92, end: 150, kind: 'zoom', scale: 1.16},
          ]}
          durationInFrames={180}
          entrySide="right"
          image="assets/screen-notification.jpeg"
          accent="cyan"
        />
      </Sequence>
      <Sequence from={1200} durationInFrames={180}>
        <ScreenScene
          kicker="Position"
          title={['Le destinataire valide sa position']}
          cues={[
            {x: 0.053, y: 0.149, w: 0.895, h: 0.26, start: 28, end: 96, kind: 'zoom', scale: 1.14},
            {
              x: 0.095,
              y: 0.253,
              w: 0.806,
              h: 0.062,
              start: 98,
              end: 150,
              kind: 'tap-zoom',
              scale: 1.2,
            },
          ]}
          durationInFrames={180}
          entrySide="left"
          image="assets/screen-location.jpeg"
        />
      </Sequence>
      <Sequence from={1380} durationInFrames={180}>
        <OutroScene />
      </Sequence>
    </AbsoluteFill>
  );
};
