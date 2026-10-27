// Background tasks must be defined before the app renders, so iOS can run them when it
// relaunches Spacetime in the background for a geofence event.
import './src/space/geofence';
import './src/lib/notifications';

import 'expo-router/entry';
