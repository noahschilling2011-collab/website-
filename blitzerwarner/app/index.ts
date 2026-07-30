/**
 * Einstiegspunkt.
 *
 * Der Background-Task muss auf oberster Ebene registriert werden, BEVOR
 * React startet. Wenn das System die App nach einem Kill neu hochfährt, um
 * eine Position zuzustellen, läuft nur dieser Modulcode — die React-Bäume
 * existieren dann noch nicht. Eine Registrierung in einem useEffect käme zu
 * spät und der Task wäre stumm.
 */
import { registerRootComponent } from 'expo';

import './src/location/task';
import App from './App';

registerRootComponent(App);
