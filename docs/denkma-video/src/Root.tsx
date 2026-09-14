import {Composition} from 'remotion';
import {DenkmaPromo} from './video/DenkmaPromo';

export const Root = () => {
  return (
    <Composition
      id="DenkmaPromo"
      component={DenkmaPromo}
      durationInFrames={1560}
      fps={30}
      width={1080}
      height={1920}
      defaultProps={{}}
    />
  );
};
