import { useEffect, useState } from 'react';
import { Keyboard } from 'react-native';

/** How much of the screen the keyboard covers (0 while it's hidden). */
export function useKeyboardHeight(): number {
  const [height, setHeight] = useState(0);
  useEffect(() => {
    const show = Keyboard.addListener('keyboardWillShow', (e) =>
      setHeight(e.endCoordinates.height),
    );
    const hide = Keyboard.addListener('keyboardWillHide', () => setHeight(0));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);
  return height;
}
